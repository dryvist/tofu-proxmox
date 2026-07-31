# Terraform Proxmox — AI Agent Documentation

Infrastructure-as-code for the Proxmox VE homelab using Terraform/OpenTofu.
This is the **infrastructure layer**; downstream Ansible repos handle
configuration management.

## Version management

**Never hardcode dependency versions unless explicitly requested.** Use latest
stable versions, let package managers resolve compatible versions, and
investigate the current ecosystem state when conflicts surface. If you find
yourself suggesting deprecated features, stop and research first.

## Technology stack

| Tool | Role |
| --- | --- |
| OpenTofu + Terrakube | Infrastructure provisioning, state, workspace locking, and run audit |
| Ansible | Configuration management (downstream repos), tested via Molecule |
| Python 3.12+ | Required by Ansible tooling |
| GitHub Actions | CI/CD (`.github/workflows/`) |
| Nix shell + direnv | Reproducible static-validation toolchain |
| OpenBao | Native workload identity and ephemeral provider credentials |
| RustFS | Private desired-state and Ansible inventory objects |

## Running Terraform / OpenTofu

Static checks run locally without credentials:

```bash
tofu init -backend=false
tofu validate
tofu test
```

Plans, applies, imports, and state operations run only in the private Terrakube
workspace. OpenBao workload identity is the sole machine-secret path. Applies
are additionally gated server-side — see below.

### Where an apply runs — not here

**`tofu apply` does not work from a workstation, by design.** Every workspace
sets `allowRemoteApply = false` — a server-side switch, so a CLI apply is
refused by the API whoever runs it. An apply is a **Terrakube job**, which is
what puts it in the run audit, under the workspace lock, and on the workspace's
own OpenBao identity. Plans are unaffected.

`fmt`, `validate`, `test`, `console`, and `plan` stay local — the fast loop.
Anything reaching the LAN (`init`, `plan`, state ops) runs from the
**`iac-platform` guest**: macOS Local Network privacy denies the ad-hoc-signed
`tofu` binary, and the symptom is a misleading `connect: no route to host`
against a healthy Terrakube.

Both in full: [docs/EXECUTION_HOSTS.md](./docs/EXECUTION_HOSTS.md).

> **AI agents**: after initial permission to run commands, an agent may run
> `tofu init` and `plan` autonomously for the session, on the pre-existing
> `tofu login` token. **`apply` is not in that set** — it is refused
> server-side and belongs to a Terrakube job: a deliberate, audited action
> rather than a step in an autonomous loop. Setup and prerequisites for the
> remote plan are in [docs/EXECUTION_HOSTS.md](./docs/EXECUTION_HOSTS.md).

## Config-file architecture (single source of truth)

```text
deployment.json (private RustFS) — desired state, topology, domain, public key
OpenBao KV                       — provider and SSH credentials
modules/proxmox-stack/locals*.tf — management_network, splunk_network_ips
```

- `deployment.json` — resource definitions (containers, VMs, pools, sizing).
  Private, not committed; fetched from homelab RustFS at plan/apply. See
  [`deployment-json-source-of-truth`](agentsmd/rules/infra/deployment-json-source-of-truth.md).
- OpenBao native KV paths supply credentials through ephemeral resources; they
  are never copied into Terrakube variables or desired-state objects.
- `management_network` and `splunk_network` are derived in
  `modules/proxmox-stack/locals.tf` and must never be set manually.

> **Warning**: `terraform.tfvars` is intentionally gitignored and must NOT
> exist. It silently overrides `deployment.json` due to Terraform variable
> precedence. If it exists in your worktree, delete it: `rm terraform.tfvars`.

### OpenBao Proxmox secret fields

| Secret | Purpose |
| --- | --- |
| `PROXMOX_VE_ENDPOINT` | API URL (without `/api2/json`) |
| `PROXMOX_VE_API_TOKEN` | API token (`user@realm!tokenid=secret`) |
| `PROXMOX_VE_USERNAME` | Username for the token |
| `PROXMOX_VE_INSECURE` | Skip TLS verification |
| `PROXMOX_VE_NODE` | Proxmox node name |

## Pipeline architecture (this repo's role)

This repo is the **single source of truth** for infrastructure: VMs,
containers, IPs, ports, and firewall rules.

> **Authority flip in design (not started).** A separately-gated effort will
> move network intent (IPs, VLANs, DNS names, firewall intent) to Nautobot as
> the source of truth, leaving this repo authoritative for **guest lifecycle
> only**. Until Phase 2 is explicitly gated open, this repo remains the source
> of truth described here — do **not** shrink `deployment.json` network fields
> or retire the published `ansible_inventory.json`. Design + boundary:
> [Phase-2 authority-flip design](https://github.com/dryvist/ansible-proxmox-apps/blob/develop/docs/nautobot/phase2-authority-flip-design.md).

- **IP derivation**: every IP is `cidrhost(network_cidrs[vlan], vm_id)`. Example
  CIDRs are `192.168.<vlan_id>.0/24`, so a compute-VLAN (id 10) VM 42 →
  `192.168.10.42`. Never hardcode IPs in any repo — they come from terraform output.
- **Pipeline constants**: `modules/proxmox-stack/constants*.tf` define
  `pipeline_constants` with service / syslog / netflow / notification /
  vector-db / AI-log port mappings, surfaced via
  `ansible_inventory.constants` in `outputs.tf`. There is no root `locals.tf`.
- **Firewall model**: default-deny, two independent layers. The guest layer
  (`modules/firewall/*.tf`) is live today — every VM/LXC gets
  `input_policy = DROP` / `output_policy = DROP` plus per-service allow
  rules keyed off `pipeline_constants` ports. The network layer (`tofu-unifi`
  inter-VLAN `LAN_IN` rules) is written to the same model but not yet
  enforced (blocked on a provider/controller rule-index gap — see that
  repo's docs). Add a new inter-VLAN flow at the guest layer first; the
  UniFi rule is written alongside it but ships `enabled = false` until the
  gap closes.
- **Media appdata**: each app's persistent config lives on its own
  `<pool>/appdata/<app>` ZFS dataset (declared in `node_storage.zfs_pools`),
  bind-mounted by `ansible-proxmox`'s `media_lxc_features` — never on the
  container's ephemeral rootfs. Sortarr (the read-only insights dashboard)
  follows this pattern with no `/data` media mount, since it never touches
  media files directly.

### Downstream repos

All three consumers resolve the inventory the same way (their
`load_tofu.yml`): `TOFU_INVENTORY_PATH` (explicit pin) → the **S3 published
artifact** (written natively by every apply via `aws_s3_object`; fetched with
`amazon.aws` modules — AWS read creds only, no checkout, no toolchain) → the
local gitignored cache. See `docs/INVENTORY_PUBLISHING.md`.

| Repo | Consumes | Purpose |
| --- | --- | --- |
| `ansible-proxmox` | `ansible_inventory` (host_services, node_storage, nodes) | Host config (kernel, ZFS, monitoring, NAS/Samba) |
| `ansible-proxmox-apps` | `ansible_inventory` (containers, docker_vms, constants, ingress) | Cribl, HAProxy, DNS, honeypots (`opencanary`, `apprise`, `tpot` roles — see `docs/HONEYPOTS.md`), etc. |
| `ansible-splunk` | `ansible_inventory` (splunk_vm + the Splunk-native HA cluster peers in `vms`) | Splunk Enterprise (Docker AIO, retiring) and the HA cluster; incl. the `honeypot` index |

### Inventory publish + sync (automatic)

Every apply publishes the inventory **natively** to the versioned state bucket
(`inventory_publish.tf`, `aws_s3_object.ansible_inventory`). `lifecycle`
preconditions on that resource validate the required inventory keys — mirroring
the ansible-proxmox-apps JSON schema — before the write, so a partial/invalid
output is rejected before anything reaches S3. The former private-data-repo
versioned-mirror PR is retired; bucket versioning on `iac-inventory` is the
safety net for a bad publish instead (see `docs/INVENTORY_PUBLISHING.md`). Each
consumer's local gitignored cache remains an offline fallback, refreshed by its
own `load_tofu.yml` resolver — not by this repo.

To sync manually after importing state without applying, see
`docs/ARCHITECTURE.md`.

## Development workflow

Static checks (`tofu fmt -check`, `tofu validate`, `tofu test`) run
automatically in pre-commit and CI — no manual invocation needed.

Credentialed operations (`tofu plan` against the live state
backend, `tofu apply`) only run in CI under OIDC, or interactively
when explicitly preparing to apply. Do not gate commits on them.

> **Never run `tofu apply -target=...`.** A partial apply still runs
> the inventory publish (see above) with an incomplete `ansible_inventory`,
> overwriting the full published artifact that all three consumer repos read.
> Always apply the whole plan.

Test in isolated resource pools, never production-first. Use feature
branches. Conventional-commit subjects only.

For slow operations and "context deadline exceeded" debugging:
[`TROUBLESHOOTING.md`](./TROUBLESHOOTING.md).

### Ansible

- Lint with `ansible-lint` before committing.
- `molecule test` for roles.
- Ensure idempotency (running twice produces no changes).
- Use FQCN (`ansible.builtin.apt`).

## Best practices

- Modular resource definitions; document variables with descriptions +
  validation; mark secrets `sensitive = true`.
- Terrakube state encrypted and restricted to workspace-scoped identities.
- Never update VMs directly; use OpenTofu or Ansible.
- Ansible: roles under `ansible/roles/` with Molecule tests; collections
  pinned in `ansible/requirements.yml`; config in `ansible/.ansible-lint`
  (profile: production).
- Security: never commit secrets, API tokens, or passwords. Real
  infrastructure values live in a separate private repo; this repo
  contains placeholders only.

## File references

| Need | Location |
| --- | --- |
| Architecture (canonical) | [`docs/ARCHITECTURE.md`](./docs/ARCHITECTURE.md) |
| Secrets roadmap | [`docs/SECRETS_ROADMAP.md`](./docs/SECRETS_ROADMAP.md) |
| Secrets hierarchy & RBAC (OpenBao KV layout, AI-agent groups) | [`docs/SECRETS_HIERARCHY.md`](./docs/SECRETS_HIERARCHY.md) |
| Secrets architecture | [`docs/SECRETS_ROADMAP.md`](./docs/SECRETS_ROADMAP.md) |
| Network-quality monitoring (SmokePing) | [`docs/SMOKEPING.md`](./docs/SMOKEPING.md) |
| Honeypots / deception fabric + phone alerting | [`docs/HONEYPOTS.md`](./docs/HONEYPOTS.md) |
| Per-WAN network diagnosis (modem/WAN telemetry) | [`docs/NETWORK_DIAGNOSIS.md`](./docs/NETWORK_DIAGNOSIS.md) |
| Troubleshooting + timeout/debug logging | [`TROUBLESHOOTING.md`](./TROUBLESHOOTING.md) |
| General docs | [`README.md`](./README.md) |
| Planning | GitHub Issues |
| Change history | PR descriptions + commits |
| Ansible config | `ansible/.ansible-lint` |
| Molecule tests | `ansible/roles/*/molecule/` |
| CI workflows | `.github/workflows/` |

## Ansible inventory output

The `ansible_inventory` output provides structured data for downstream
Ansible. The full shape is assembled in `local.ansible_inventory`
(`inventory_publish.tf`) and shared by both the `ansible_inventory` output
(`outputs.tf`, a one-line passthrough) and the native `aws_s3_object`
publish resource:

```hcl
local.ansible_inventory = {
  containers    = { ... }
  vms           = { ... }
  docker_vms    = { ... }
  splunk_vm     = { splunk = { vmid = 200, hostname = "splunk-aio", ip = "<derived>" } }
  constants     = local.pipeline_constants
  ingress       = { ... }
  host_services = var.host_services
  nodes         = { ... }
  node_storage  = { ... }
  domain        = var.domain
}
```

## When to ask for clarification

Stop and ask before proceeding if any of the following are true:

- Current tool versions are unclear.
- Multiple valid implementation approaches exist.
- Changes affect production infrastructure.
- Security implications are uncertain.
- Breaking changes may be introduced.

## PR review checklist

- [ ] No exposed secrets or credentials.
- [ ] Variables documented; `sensitive = true` where appropriate.
- [ ] `tofu validate` passes.
- [ ] `ansible-lint` passes (if Ansible touched).
- [ ] `molecule test` passes (if Ansible roles touched).
- [ ] Conventional commit message.
- [ ] Documentation updated where needed.
