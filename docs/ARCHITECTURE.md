# Architecture

## Control plane

Terrakube runs OpenTofu inside the homelab. It owns state, workspace locking,
job ordering, and audit history. Its per-job identity is exchanged directly
with OpenBao for a short-lived workspace token. Executors install providers
and modules from the homelab mirror, so routine plan/apply does not require
public internet.

```text
Terrakube workspace lock
  -> per-job workload identity
  -> OpenBao workspace policy
  -> ephemeral provider credentials
  -> OpenTofu plan/apply
```

## Inputs

The private, versioned RustFS `deployment.json` is desired state: guests,
pools, storage declarations, topology, domain, and the public SSH key. OpenBao
stores all credentials and private keys. The root configuration reads both
natively and passes typed values to `modules/proxmox-stack`.

OpenBao cluster peers are expanded deterministically from the shared cluster
shape in the deployment object. The root contract fails closed when load-
bearing collections or topology values are absent.

## State and locking

Terrakube state replaces the former object-store backend and lock table.
Workspace locking is sufficient; the general OpenBao flow-lock authority is
not used for OpenTofu. `migrations.tf` moves existing resource addresses under
the wrapper module without recreating infrastructure. The actual state import
requires an approved production migration window.

## Networking and firewall

Every static address is derived with `cidrhost(network_cidrs[vlan], vm_id)`.
DHCP-first guests use deterministic MACs and reserved host numbers. Guest
firewalls remain default-deny with service flows derived from
`pipeline_constants`; the UniFi layer consumes the same model in `tofu-unifi`.

## Splunk storage tiers

Splunk index storage is split into three tiers with distinct durability
postures. The first two are declared here (VM disks + `node_storage` datasets);
the frozen tier is configured Splunk-side in `ansible-splunk`.

| Tier | Where | Pool / backing | RAID | Backup posture |
| --- | --- | --- | --- | --- |
| `fast-splunk` (hot + warm) | fast/NVMe node, `virtio2` | mirror pool, `pvesm_id = fast-splunk` | mirror | `backup = false` by design — B2 replaces it |
| `bulk-splunk` (cold) | bulk-capable node, `virtio3` | dedicated non-RAID pool, `pvesm_id = bulk-splunk` | none (single disk) | `backup = false` by design — B2 replaces it |
| B2-frozen (archive) | Backblaze B2 (off-site), dedicated `splunk` bucket | S3 bucket via `secrets-external/platform/backblaze-splunk` | n/a (cloud-durable) | is the durable copy, but **offline** — no object layout makes frozen data searchable; recovery is a deliberate thaw |

The archive credential reads from `secrets-external/platform/backblaze-splunk`,
which carries Splunk's own dedicated bucket. Splunk no longer shares the
Postgres-backups credential — a shared bucket gives no separate lifecycle
policy and no blast-radius boundary. The upload and restore were both exercised
against the live endpoint before this was written.

Neither Splunk index disk gets block-level backup. Index data is
reconstructible, and block backups would roughly double the storage consumed
for no resilience gain — resilience here comes from being cleanly
rebuildable, not from disk backups. Durability for data worth keeping comes
from the Backblaze B2 frozen tier at the Splunk layer, never from Proxmox
`vzdump`. Do not re-enable `backup = true` on either tier without revisiting
this decision.

`bulk-splunk` is additionally non-RAID and excluded from Proxmox `vzdump`: ZFS
RAID is pool-wide, so a non-RAID cold tier cannot share a raidz pool. The
`fast-splunk` dataset is registered as its own Proxmox `zfspool` storage id (via
its dataset `pvesm_id`) so the VM disk targets it directly instead of landing at
the pool root. The legacy `virtio1` 200G data disk stays attached transitionally
until a separate migration moves data onto the tiers — see
[`INFRASTRUCTURE_NUMBERING.md`](./INFRASTRUCTURE_NUMBERING.md) and
[`SPLUNK_VM_DISK_DRIFT.md`](./SPLUNK_VM_DISK_DRIFT.md).

The architectural rule intended Splunk-side (in `ansible-splunk`, not here): a
Splunk index may not be defined without pointing its `homePath`/`coldPath` at one
of the two custom volumes (`fast-splunk` / `bulk-splunk`). This repo only
declares the volumes and publishes them as `splunk_storage` in the inventory; it
does not define indexes. **Not yet enforced**: as of this writing,
`ansible-splunk`'s `indexes.conf.j2` emits flat `$SPLUNK_DB` paths with no
volume stanzas, so no index currently targets either tier — enforcement is in
progress, not current state.

## Downstream inventory

A full apply publishes the versioned Ansible inventory to RustFS as a native
resource. `ansible-proxmox`, `ansible-proxmox-apps`, and `ansible-splunk` fetch
that object on the homelab network. The producer graph validates required
connection and ingress fields before publication.

## Secret-bearing feature transfers

- Route53 uses OpenBao's native AWS secrets engine for ephemeral STS sessions.
- Servarr API keys are ephemeral; qBittorrent wiring stays in the Ansible
  `servarr_wiring` role because the provider cannot accept ephemeral secrets.
- Provider arguments that cannot be write-only require encrypted, tightly
  scoped Terrakube state until ownership can move to a native Ansible path.
