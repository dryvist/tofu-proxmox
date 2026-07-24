# Infrastructure Numbering Scheme

**Status**: Active. The homelab has moved to a **6-7-digit tier-positional VMID** scheme.
The legacy flat 3-digit IDs (100-251) still exist and are renumbered incrementally as
maintenance windows allow — they are **not** the target.

> The authoritative, digit-by-digit allocation is **not** duplicated here (it drifts).
> Canonical design + tier tables: **[docs.jacobpevans.com/infrastructure/vmid-network-tiers](https://docs.jacobpevans.com/infrastructure/vmid-network-tiers)**
> (the public page is the framework; the exhaustive per-guest allocation is in the private
> infrastructure docs). The **live** per-guest assignment is the gitignored
> `deployment.json` and the `ansible_inventory` Terraform output — this file describes the
> *convention*, not the inventory.

---

## Hostname & Multi-Instance Naming Law

**FUTURE LAW**: For all new multi-instance containers or VMs, the hostname suffix MUST be two digits where the **first digit is the Proxmox node ID**.
For example, instead of `zammad-1` and `zammad-2`, use `zammad-20` (Node 2, instance 0) and `zammad-30` (Node 3, instance 0).

## The VMID positional scheme (current)

```text
[Tier][Sub-tier][Crit][OS][Instance][Env]
   │      │        │    │      │       │
   │      │        │    │      │       └─ environment (prod / stg / test / dev / sbx)
   │      │        │    │      └───────── instance number within the group
   │      │        │    └──────────────── OS family (0 = LXC, the common case)
   │      │        └───────────────────── criticality 0-9 (lower = more critical; 5 = default)
   │      └────────────────────────────── sub-tier (0 user-facing, 1 mgmt, 2 download)
   └───────────────────────────────────── trust tier 1-9 (= VLAN tag ÷ 10)
```

A plain numeric sort groups guests by tier → sub-tier → criticality, for free. Example:
Plex (`702000`) = tier 7 (media) · sub 0 (user-facing) · crit 2 · OS 0 (LXC) · instance 0 ·
env 0 (prod), and lives on VLAN 70 — identity and network are one number.

### Trust tiers → VLANs (tier × 10)

| Tier | VLAN | Name | What lives here |
| --- | --- | --- | --- |
| 1 | 10 | Core services | Foundational infra everything depends on |
| 2 | 20 | Storage | NAS, block/object storage, backup targets |
| 3 | 30 | Data / pipeline / compute | Data movement, batch, general compute |
| 4 | 40 | Observability & security | Monitoring, logging, security tooling |
| 5 | 50 | AI / ML | Inference, training, model-serving |
| 6 | 60 | Applications | General self-hosted apps |
| 7 | 70 | Media | Media library + supporting services |
| 8 | 80 | Home & IoT | Home automation, IoT |
| 9 | 90 | Untrusted / guest | Cameras, guest access, least-trusted |

Special-purpose VLANs sit **outside** the tier numbering: `1` Default, `5` Management,
`53` DNS (named for port 53).

---

## Addressing: DHCP / DNS-first, with a static exception

Guests do not carry hardcoded IPs. The default is **DHCP + DNS-first**: a guest is referenced
everywhere by `{hostname}.{subdomain}` and DNS owns the actual lease. In `deployment.json` a
DHCP-first guest sets `dhcp: true` (+ optional `reserved_host` octet for a deterministic
DHCP reservation pinned by tofu-unifi). IaC carries hostnames, not octets.

The **exception** is core gear that must be reachable *before* DNS is up — most importantly
**DNS servers**. These pin a static `ip_config.ipv4_address` instead.

How `locals.tf` resolves a guest's address (`container_ipv4`):

- `dhcp = true` → `"dhcp"` (no IP derived; gateway null, lease-provided).
- static `ip_config` set → that address.
- otherwise → `cidrhost(network_cidrs[vlan], vm_id)` (legacy derive; only valid while the ID
  fits the /24).

`cidrhost` is evaluated **only** on the derive branch (an if/else, not `coalesce`, so it
short-circuits — see PR #444). That is what lets a static-IP exception host carry a 6-7-digit
positional VMID: a `cidrhost(cidr, 5310090)` would overflow the /24, but it is never
evaluated when a static `ip_config` is present.

### DNS servers (special VLAN 53, static exception) — worked example

DNS = VLAN 53, outside the tier÷10 rule, so DNS guests use a **7-digit `53`-prefixed** ID and
a **static** IP. An illustrative DNS secondary (the real IDs live only in `deployment.json`):

- VMID **5310090** = `53` (DNS VLAN) · sub 1 (mgmt) · crit 0 (most critical) · OS 0 (LXC) ·
  instance 9 · env 0 (prod).
- static `ip_config` `<dns-subnet>.3` (gateway `.1`, primary `.2`, secondary `.3`).

> IP examples on this page use the `192.168.<vlan>.x` placeholder shape (committed-file rule);
> real subnets come from OpenBao `NETWORK_CIDR_*` at runtime and live only in the gitignored
> `deployment.json`. See [AGENTS.md](../AGENTS.md) for the config-file architecture.

---

## Legacy 3-digit ranges (being retired)

The original flat scheme assigned IDs by function in 100-299. These guests still run on these
IDs until renumbered onto their tier-positional IDs; treat the table as historical, not as the
allocation to extend.

| Range | Legacy purpose |
| --- | --- |
| 100-110 | Infrastructure containers |
| 150-169 | AI development containers |
| 171-189 | Cribl Stream / Edge containers |
| 190-199 | Load balancer / HAProxy / Splunk mgmt |
| 200 | Splunk Enterprise VM |
| 201-299 | Reserved for future VMs |

New guests adopt the positional scheme immediately; do not assign new flat 3-digit IDs.

---

## Resource pools

Guests are grouped into Proxmox resource pools by function (`pool_id` in `deployment.json`),
e.g. `infrastructure`, `ai`, `logging`, independent of the VMID. Pools are organizational;
placement on a node's VLAN is driven by the tier, not the pool.

---

## Splunk configuration

### Architecture

**Target (Phase 3): a Splunk-native HA cluster** on the `siem` VLAN (tier 4),
declared in the `vms` map of `deployment.json` (see the `_splunk_cluster_comment`
in `deployment.json.example`) and converged by the ansible-splunk `splunk.splunk`
role (`docs/SPLUNK_CLUSTER_DESIGN.md` there):

- **`splunk-idx-10` / `splunk-idx-40`** (`421100` / `421110`): a 2-peer indexer
  cluster, replication/search factor 2, one peer per node (proxmox-1, proxmox-4).
- **`splunk-sh-10` / `splunk-sh-40`** (`421120` / `421130`): two independent
  search heads (not an SHC — an SHC needs 3 members).
- **`splunk-mgmt-40`** (`421140`): cluster manager + license master + monitoring
  console + a third unclustered search head.

Positional decode `4211I0` = tier 4 · sub 2 (SIEM data plane) · crit 1 · OS 1
(VM) · instance I · env 0.

**Legacy (being retired):** the single all-in-one Splunk Enterprise VM (`200`,
`splunk_vm_id`) plus the `splunk-mgmt` container (`199`). The AIO is
disable-never-delete and kept as a distributed search peer during migration.

### Port matrix

| Port | Protocol | Purpose             | Allowed From            |
| ---- | -------- | ------------------- | ----------------------- |
| 22   | TCP      | SSH                 | management_network      |
| 8000 | TCP      | Splunk Web UI       | management_network      |
| 8088 | TCP      | Splunk HEC          | Splunk network + Cribl  |
| 8089 | TCP      | Splunk Management   | Splunk network          |
| 9997 | TCP      | Splunk Forwarding   | Splunk network + Cribl  |
| 8080 | TCP      | Replication         | Splunk network          |
| 9887 | TCP      | Clustering          | Splunk network          |

---

## Storage configuration

### Cribl persistent-queue disks

Cribl Stream and Cribl Edge containers carry a separate data disk for the on-disk persistent
queue (mounted at `/opt/cribl/data`): a small root disk for OS + application, plus a larger
data disk so a HAProxy/Cribl outage buffers instead of dropping. Ansible formats and mounts
the data disk; see the Cribl roles in the downstream apps repo.

### Splunk VM disk layout

The Splunk VM carries a boot disk, a legacy data disk, and two tiered storage
disks:

- **Boot disk**: OS, Splunk application, configuration. Declared `virtio0`; the
  live disk has drifted to `scsi0`/50G — see
  [`SPLUNK_VM_DISK_DRIFT.md`](./SPLUNK_VM_DISK_DRIFT.md).
- **Legacy data disk (`virtio1`, 200G)**: current Splunk index storage, mounted
  at `/opt/splunk/var`. Transitional — kept attached until a separate migration
  moves data onto the tiered disks below.
- **`fast-splunk` (`virtio2`)**: hot + warm buckets on the fast/NVMe tier
  (`datastore_id = fast-splunk`, backed up).
- **`bulk-splunk` (`virtio3`)**: cold buckets on the non-RAID cold tier
  (`datastore_id = bulk-splunk`, `backup = false` by design; archived to
  Backblaze B2).

Disk sizes are set in `deployment.json`: `splunk_boot_disk_size`,
`splunk_data_disk_size` (legacy `virtio1`), `splunk_fast_disk_size` (default
1024), and `splunk_bulk_disk_size` (default 2048). The tiered disks are declared
but do not attach until the disk-drift reconciliation completes (see the drift
doc). See [`ARCHITECTURE.md`](./ARCHITECTURE.md) for the per-tier RAID/backup
posture.

---

## Terraform management

All guests, pools, and firewall rules are 100% Terraform-managed; the live set of resources is
defined in `deployment.json` and surfaced to downstream Ansible via the `ansible_inventory`
output. Deploy from scratch with `tofu apply`.
