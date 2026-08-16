# Autonomous DR / HA

The disaster-recovery / high-availability design for the cluster. Owner law:
**DR/HA must be 100% autonomous** — no manual step to detect an outage or switch
nodes. Resilience comes from being cleanly rebuildable and from app-layer
redundancy, not from un-killable guests (ChaosMonkey philosophy).

The cluster runs **four** nodes (`proxmox-1..4`), all quorate. With four real
corosync votes, losing one node keeps quorum (quorum = 3), so HA fencing is safe
— no surviving node self-fences.

The tier-0 guests that must survive a node failure:

| Guest(s) | Redundancy mechanism | DR wave |
| --- | --- | --- |
| ingress (`traefik`, future `traefik-2`) | keepalived VRRP VIP floats across nodes | W1 + W5 |
| OpenBao (nine Raft voters, see W6) | Raft quorum | W6 |
| DNS (`technitium-dns`, `technitium-dns-2`) | two independent instances | W5 |

## W4 — corosync vote integrity

Target: exactly **N real votes for N nodes**, with **no `two_node` and no manual
`expected_votes` override** in `corosync.conf`. A leftover 2-node override from
the pre-multi-node era changes the quorum math and would break fencing (a lone
survivor could stay quorate and skip self-fencing).

Verified live: four nodes, Expected votes 4, Quorum 3, Quorate — clean, no
overrides. Regression is guarded by `ansible-proxmox`'s `pve_cluster` role,
which fails loud on the primary if either override reappears.

## W5 — PVE HA rules (`ansible-proxmox` `pve_ha` role)

Models Proxmox VE 9 HA (the new "HA rules", not legacy HA groups) as IaC. Inert
by default; enabling is a deliberate, gated step.

When enabled it:

1. Places each tier-0 LXC under HA (`ha-manager add ct:VMID --state started
   --max_restart 3 --max_relocate 1`). VMIDs resolve from the tofu inventory by
   hostname, so a renumber flows through with no edit.
2. Adds `resource-affinity` **negative** rules so redundant peers never share a
   node — the Technitium DNS pair and the Traefik ingress pair. The OpenBao
   voters are a nine-member Raft set, not a pair; their spread is a placement
   problem (see W6), and a negative rule over all nine would be unschedulable
   on four nodes.

**Why anti-affinity is the payload, not relocation.** These guests sit on
**local ZFS**, not shared storage, and each already has a redundant peer on
another node. So a crash auto-restarts the guest in place, and a node loss is
covered by the surviving peer (the failed guest returns when its node heals).
Live cross-node relocation would need PVE storage replication (`pvesr`) — a
tracked follow-up, deliberately **not** required for the node-loss story. Hence
`max_relocate` is low; anti-affinity is what keeps each pair genuinely split.

A non-destructive failover drill
(`ansible-proxmox` `scripts/ha-failover-drill.sh`) proves auto-restart +
relocation against a disposable test guest only.

## W6 — OpenBao Raft: nine members, still unevenly placed

**Verified live**: nine members, every one `initialized` and unsealed, all
reporting the same cluster id, with one elected leader. Each carries a real
config and live Raft data — the `openbao_cluster` generator's guests are
converged members, not shells.

| Member | VMID | Node | Voter |
| --- | --- | --- | --- |
| `openbao-01` | 110040 | `proxmox-1` | yes |
| `openbao-10` | 110010 | `proxmox-1` | yes |
| `openbao-02` | 110140 | `proxmox-2` | yes |
| `openbao-20` | 110020 | `proxmox-2` | yes |
| `openbao-21` | 110021 | `proxmox-2` | yes |
| `openbao-30` | 110030 | `proxmox-3` | yes |
| `openbao-31` | 110031 | `proxmox-3` | yes |
| `openbao-41` | 110041 | `proxmox-4` | yes |
| `openbao-42` | 110042 | `proxmox-4` | yes |

Per node: **`proxmox-1` 2 · `proxmox-2` 3 · `proxmox-3` 2 · `proxmox-4` 2.**
The explicit `openbao-01` / `openbao-02` entries in the `containers` map and the
`openbao_cluster` generator's suffixes are **both live** — they are one cluster,
not two competing schemes.

Every row comes from a direct read of `sys/storage/raft/configuration`, which
showed all nine `voter=true` with one elected leader. The `proxmox-4` pair were
previously recorded here as `unverified`, because reading the flag back needs a
capability no routine role carries. That gap is now closed by measurement: the
pair are **full voters**, not declared-but-unconfirmed, so the earlier advice to
size them as voters and depend on them as non-voters no longer applies.

Read voter membership from the Raft configuration, never from `sys/health`. A
member that has fallen out of the cluster still answers health — that check is
satisfied by the exact state it is meant to rule out, so it cannot detect the
failure it is there to catch.

### Voter addressing: static and derived, never leased

Every voter's `ip_config` is `cidrhost()` over the cluster's own VLAN CIDR and
the peer suffix (`main.tf`'s `openbao_generated_containers`), not `dhcp` plus a
reserved octet. OpenBao is critical-tier — every guest in the estate resolves
its credentials here, so a voter that changed address on a lease renewal would
force a re-converge of everything pointing at it. The address is declared in
exactly one place and nothing mirrors it into a controller reservation or a
separately published DNS record, so there is no second copy to disagree with.
This briefly moved to `dhcp` + a reserved octet; that made a critical service's
address depend on a lease *and* declared the address a second and third time,
in the reservation and the zone — reverted.

### The real risk: voter concentration, not voter count

All nine members are voters, so **quorum is 5**. Losing `proxmox-2` removes
**3** at once, leaving 6 — quorum holds with **one loss of headroom**. Losing
any other single node removes 2, leaving 7.

That is better than the seven-member layout it replaced, where losing
`proxmox-2` left exactly quorum and any further loss sealed the cluster. The
concentration itself has not been fixed: `proxmox-2` still carries three, so it
is still the node whose loss costs the most. An even spread is the remaining
work, and it is a placement change in `deployment.json` plus a converge — never
a hand-run membership edit.

**Autopilot's `failure_tolerance` hides this.** It counts *server* losses and is
blind to which hypervisor each member sits on. Independent guest failures are
survivable up to that number; **one hypervisor failure plus one guest may not
be.** Never read `failure_tolerance` as a node-loss budget.

**Before taking a node out deliberately**, count what is left rather than
trusting this table — placement moves. Do not overlap a planned node outage
with any other work that stops a member.

### Removing an OpenBao guest — mandatory precondition

An earlier revision of this document described five of the above voters as
"orphan shells ... never converged" and prescribed removing them. **That was
false, and following it would have destroyed 5 of 7 voters including the
leader**, sealing the cluster. The procedure is deleted; do not reconstruct it
from history.

If a future OpenBao guest genuinely is an unconverged shell, **prove it before
removing anything**:

```sh
bao read -format=json sys/storage/raft/configuration \
  | jq -r '.data.config.servers[].node_id'
```

A guest whose `node_id` **appears in that output is a live Raft voter.** It is
removable only through a deliberate, gated peer-removal — never as inventory
cleanup, never as a side effect of a `deployment.json` edit or a `tofu apply`.
Removing a guest that is absent from that list is safe.

Two standing hazards remain regardless:

- **VMID collision:** generator suffix `40` maps to the same VMID as the
  explicit `openbao-01`. Any placement using suffix 40 collides.
- **`protection: true`** on the OpenBao containers is a repo-law violation (no
  destroy-protection). Removed from the generator defaults in
  `deployment.json.example`; clearing it on the live containers is a gated
  apply. Note that with a healthy cluster this flag has been the last thing
  standing between the bad procedure above and a sealed cluster — clear it only
  once the precondition check above is part of the workflow.

**Unseal / recovery:** the shared static-key auto-unseal means a peer unseals
itself on start; a join never re-inits and never touches the recovery shares.
Every member inherits the automated raft-snapshot timer on converge.

## Media tier

Deliberately **no cluster HA and no vzdump** for the media guests — every one
rebuilds from IaC alone, proven by a live `seerr` destroy/recreate canary
(container replaced, 117-request history intact). The protection budget goes to
the irreplaceable per-app state instead:

- Each app's config/DB lives on its own `bulk/appdata/<app>` dataset,
  bind-mounted over the app's config dir by `ansible-proxmox`
  `media_lxc_features` (seed-before-mount on first cutover).
- `bulk/appdata` is on the sanoid `critical` template (hourly, recursive) and
  syncoid-replicated from the bulk-storage node to the DR node. **The two
  cadences are not the same, and the off-node one is what an RPO is measured
  against.** Snapshots are local and hourly; the DR leg pulls them on the
  daily syncoid schedule, so a snapshot can wait a full day before a copy
  exists off-node. **Off-node RPO for `bulk/appdata` is therefore ~24 h, not
  ~1 h** — up to a day of app config/DB changes exists only on the
  bulk-storage node. Shrinking it means raising how often the DR leg *pulls*
  (the syncoid schedule on the DR node); adding sanoid frequency on the
  source does nothing for it.
- The `bulk/data` library itself is deliberately **unsnapshotted and
  unreplicated** (`com.sun:auto-snapshot=false`): torrent churn makes snapshots
  expensive and the payload is re-acquirable, so a loss is a re-download, not a
  disaster.
- Rebuild path: OpenTofu recreates the LXC → `media_lxc_features` re-mounts the
  persisted appdata (seed skipped, dataset non-empty) → the app role reinstalls
  the runtime. No manual step; vzdump would only duplicate what IaC + appdata
  already guarantee.
