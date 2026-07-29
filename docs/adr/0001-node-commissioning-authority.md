# ADR 0001 — Which source is authoritative for "is this node real?"

- **Status**: Proposed — needs an operator decision
- **Date**: 2026-07-29

## Context

Placing an OpenBao Raft voter on the fourth cluster node surfaced a question the
IaC cannot answer: **is that node commissioned?** Two repos disagree.

| Source | Says |
| --- | --- |
| this repo's node declaration | `commissioned: false` — "declared but not yet installed" |
| `ansible-proxmox` `inventory/hosts.yml` | `pve_node_commissioned: true`, "always-on", already joined, listed in `pve_cluster_members` |

Reality sits with the second: the node is a cluster member running guests. A
design note already records a container assigned to it, and the retirement plan
for the ageing node contemplates rebuilding OpenBao voters there.

### Both flags are documented to enforce things they do not

This is what makes it a decision rather than a typo. Verified by reading the
code, not the comments:

| Flag | Documented as | What it actually gates |
| --- | --- | --- |
| `nodes.<n>.commissioned` (this repo) | "no workloads are placed on it and its `node_storage` is not applied until it is brought online" | **Only** membership in the Proxmox UI ingress backend pool (`locals-ingress-backends.tf`) — its sole reader. |
| `pve_node_commissioned` (`ansible-proxmox`) | "`zfs_pools` gates pool creation on `pve_node_commissioned`" — stated in `roles/pve_cluster/README.md` and `playbooks/cluster.yml` | **Nothing.** No task in `roles/zfs_pools/` references it. |

The only enforced storage gate lives in `roles/zfs_pools/`: a pool is created
when `zfs_pools_allow_create` is true **and** the node has a layout in
`node_storage`. Registration and dataset management key off the same layout.

So the de-facto authority today is **`node_storage`**, because it is the only
thing with teeth. Two flags that read like safety interlocks are unenforced
prose.

### Why this is load-bearing now

Nothing stops a workload landing on a node flagged `commissioned: false`. The
`openbao_cluster` generator, for one, iterates `placement` without consulting
the flag — so adding a fourth node's suffixes would create Raft voters on a node
this repo calls uninstalled, silently and without warning.

Three findings, one root cause:

1. A node flagged uninstalled here is a live cluster member elsewhere.
2. A node carrying multiple TiB of migrated data is declared by **neither** this
   repo's node list nor `ansible-proxmox` `host_vars/`.
3. Guest `602000` runs a live `*/5` replication job while absent from the
   published inventory.

**Live state the IaC does not know about, and declared state the IaC does not
enforce.** While two repos disagree about which nodes exist, no placement
decision can be made safely — a quorum member least of all — and an apply may
not know to preserve live state it never declared.

## Decision needed

Pick one source of truth for node commissioning, and make the other defer to it
or match it.

### Option A — this repo is canonical, and the flag gets teeth

`nodes.<n>.commissioned` becomes the single declaration. Implement what its
comment already claims: guest placement and `node_storage` application both
refuse an uncommissioned node. `ansible-proxmox` drops its own flag and reads
this one from the published inventory.

*For:* one declaration, already the de-facto authority, and the enforcement gap
closes. *Against:* the largest change, and it hard-fails applies that currently
succeed — including any guest that has already drifted onto the fourth node.

### Option B — this repo is canonical for identity, `ansible-proxmox` for readiness

Keep both flags, give them non-overlapping meanings, and rename accordingly:
this repo declares *the node exists in the cluster*; `ansible-proxmox` declares
*this node is ready to be converged*. Correct both doc comments to describe what
the code actually does.

*For:* smallest diff, matches how the flags are already used, changes no runtime
behavior. *Against:* two flags remain, and the next reader still has to learn
which is which.

### Option C — delete both flags

Neither is enforced where it is documented. Remove them and let presence in
`node_storage` be the only signal: a node with a layout is commissioned, a node
without one is not.

*For:* deletes unenforced prose instead of implementing it — the truthful
option. *Against:* loses the ability to declare a node ahead of installing it,
which the ingress pool filter genuinely uses.

**Recommendation: Option B, then revisit.** It is the only one that lands
without changing runtime behavior, and correcting two false comments is worth
more today than crowning a winner. A wrong doc comment is what let the "orphan
shells" claim in [`DR_HA.md`](../DR_HA.md) survive long enough to become a
runnable procedure that would have removed five live Raft voters.

## Consequences

Until this is decided:

- **No voter placement on the fourth node.** Not because it is unfit, but
  because its status has no authoritative answer, and a quorum member is the
  wrong place to discover we guessed wrong.
- A `node_storage` layout for that node remains a prerequisite under all three
  options, since each keeps it as the storage gate.
- Authoring that layout needs the node's real disk topology, which is in no
  repo and cannot be derived without reading the host.
