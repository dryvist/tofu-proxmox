# Terrakube and OpenTofu Troubleshooting

## A run is waiting

Terrakube serializes runs per workspace. Inspect the private Terrakube job
queue and cancel only a confirmed abandoned job. Do not create or bypass a
second OpenBao lock. A lost executor does not leave a separate backend lock.

## OpenBao authentication fails

Verify the Terrakube workload issuer and JWKS endpoints from the homelab, then
confirm the workspace role binds the exact audience, organization, project,
and workspace claims. Do not fall back to a stored AppRole secret or root
token.

## RustFS desired state cannot be read

Check the native OpenBao path
`secret/platform/object-storage`, RustFS DNS/TLS reachability,
and the `iac-inventory/deployment.json` object. The configuration fails closed;
never substitute an empty object.

## Proxmox is slow or unreachable

Run `scripts/check-proxmox-api.sh` only from an approved OpenBao-authenticated
operator session. Check the Proxmox endpoint stored at
`secret/infrastructure/proxmox`, cluster health, and internal DNS. Keep all
writes inside the Terrakube workspace.

## State recovery or import

Prefer a private Terrakube state operation so the workspace lock and audit trail
remain authoritative. Local state edits are a **break-glass** path, not a blanket
prohibition: when Terrakube is confirmed down, `tofu-proxmox` may init directly
against a valid backend and operate on state locally.

- The legacy S3 + DynamoDB backend stays valid for **30 days** after cutover.
  Within that window `tofu init -backend-config=` against the legacy bucket and
  lock table is a supported rollback target.
- After the legacy backend is retired, use the direct RustFS S3 backend instead
  — see `iac-platform` `docs/fleet-migration.md` → "Break-glass recovery" for the
  backend block, the OpenBao credential path, and the SOPS-bootstrap fallback.

**Single-operator rule.** A direct backend cannot see Terrakube's Postgres lock.
Confirm Terrakube is down, hold the `flow-lock --flow tofu-breakglass` lease (one
operator), snapshot with `tofu state pull` first, and run a full plan (never
`-target`). Return to Terrakube runs once the platform is healthy.

### Retired `vault-secrets` root

The `vault-secrets` OpenTofu root was removed. Its live state is intentionally
**abandoned** in the legacy S3 backend (retained 30 days, then deleted with the
rest of the legacy estate) — this is a **0-destroy** change: no `tofu destroy`
runs, and the KV secrets it wrote (`secret/apps/{nautobot,zammad}`) are untouched
in OpenBao. Generation of those app secrets now belongs to the human-gated
`openbao` Ansible role (`ansible-proxmox-apps`, generate-if-absent), so nothing
needs to import or re-apply the abandoned state.

## Provider installation without internet

Terrakube executors use the homelab provider/module mirror configured by the
platform. If initialization attempts public registry access, stop the run and
repair the mirror configuration; do not grant temporary egress.

## Moving a guest

Before stopping or migrating any guest:

1. Read its HA rules. Strict node-affinity rules limit its allowed nodes.
2. Call `GET /nodes/<node>/qemu/<vmid>/migrate?target=<node>` to check
   allowed nodes and migration blockers for a VM.
3. Check target storage for a stale volume with the same VMID. An orphaned
   `vm-<vmid>-cloudinit` volume aborts storage migration with "volume already
   exists". Remove it only after confirming the VM's config is not on the
   target node.
4. Confirm the target node has enough memory.

A live migration between AMD and Intel nodes can hang a running VM, even with
a generic CPU model such as `x86-64-v2`. The provider live-migrates a running
HA VM on any `node_name` change. Move the VM cold: stop it, migrate it offline,
and start it. Then set `node_name` and `cpu_vendor` together and confirm the
plan shows no move. The `cpu_vendor` placement guard refuses a mismatch at
plan time. HA failover may cross vendors because it cold-restarts from a
replica.

Never let an apply move the VM that hosts its Terrakube runner. The run kills
its own executor, the local CLI may exit 0, and the job remains orphaned. Move
the runner VM cold by hand first, then apply. See
[apply verification](docs/INVENTORY_PUBLISHING.md#verify-an-apply) for the
completion checks.
