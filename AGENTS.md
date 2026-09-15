---
skill-groups: [core, git, homelab]
---
# Terraform Proxmox — AI Agent Documentation

IaC for the Proxmox VE homelab (Terraform/OpenTofu) — the **infrastructure
layer**; downstream Ansible repos handle configuration management.

## Version management

**Never hardcode dependency versions unless explicitly requested.** Use
latest stable versions and let package managers resolve compatible ones.
Research the current ecosystem state on conflicts; don't suggest deprecated
features.

## Technology stack

| Tool | Role |
| --- | --- |
| OpenTofu + Terrakube | Provisioning, state, workspace locking, run audit |
| Semaphore | Ansible management plane; run execution |
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
tofu test                      # ROOT ONLY — see below
./scripts/tofu-test-modules.sh # every module suite
```

> **`tofu test` at the root runs none of the module suites.** It doesn't
> recurse into `modules/*/tests`, so alone it reports `Success! 0 passed, 0
> failed` and exits 0 — a passing badge over an empty run. The real
> assertions live in `modules/*/tests`; the script above derives the suite
> set from the tree, prints the assertion count, and fails if it's zero.

### Where an apply runs — not here

Plans, applies, imports, and state ops run only in the private Terrakube
workspace, on OpenBao workload identity (the sole machine-secret path).
**`tofu apply` never works from a workstation, by design**: every workspace
sets `allowRemoteApply = false` server-side, refusing any CLI apply — apply
happens only as an audited, workspace-locked **Terrakube job** on the
workspace's own OpenBao identity, never an autonomous step. `fmt`,
`validate`, `test`, `console`, `plan` are unaffected and run anywhere,
including autonomously by an AI agent on the pre-existing `tofu login`
token — `apply` is excluded from that set. GitHub pushes do **not** trigger
Terrakube jobs; trigger one via the Terrakube API directly, using the token
in `~/.terraform.d/credentials.tfrc.json` on the execution host (e.g.
`curl -X POST .../api/v1/organization/<org-id>/job`).

> On macOS, `tofu` is ad-hoc-signed and gets denied against a backend on a
> directly-attached subnet — symptom is a misleading `connect: no route to
> host` against a healthy backend. A routed path avoids this; don't
> diagnose it as an outage.
>
> **Set `TF_WORKSPACE` explicitly** when exporting backend coordinates by
> hand. The stored default is a different workspace; picking it up silently
> fails as a fake credential outage (403 plus 401), not a wrong-workspace
> error. Confirm the workspace in the run URL the plan prints.

Workspace specifics are environment-specific and are not recorded here.

## Config-file architecture (single source of truth)

```text
deployment.json (private RustFS) — desired state, topology, domain, public key
OpenBao KV — provider and SSH credentials
modules/proxmox-stack/locals*.tf — management_network, splunk_network_ips
```

- `deployment.json` — resource definitions (containers, VMs, pools, sizing).
  Private, not committed; fetched from homelab RustFS at plan/apply. See
  [`deployment-json-source-of-truth`](agentsmd/rules/infra/deployment-json-source-of-truth.md).
- **Node placement is a standard, not a free choice** — nodes differ by an
  order of magnitude in RAM, by CPU generation, and by which holds the bulk
  dataset, so placement follows the binding constraint named in the guest's
  `description` field. The standard (node roles, rules, per-node overcommit
  ceiling) is topology, kept in private docs. **`node_name` is `ForceNew`**:
  changing it plans a destroy-and-recreate of a running guest — see
  `imports.tf`.
- OpenBao native KV paths supply credentials through ephemeral resources —
  never copy them into Terrakube variables or desired-state objects.
- `management_network` and `splunk_network` are derived in
  `modules/proxmox-stack/locals.tf` — never set manually.

> **Warning**: `terraform.tfvars` is intentionally gitignored and must NOT
> exist — it silently overrides `deployment.json` via Terraform variable
> precedence. If it exists in your worktree, delete it: `rm terraform.tfvars`.

### Provider credentials

Supplied to the provider through ephemeral resources. Field list, source
store, and how to obtain them are documented privately, not restated here —
a prior table here named fields that don't exist and broke consumers at run
time. The node to act on is **not** a credential: it comes from
`deployment.json` (`proxmox_node`).

## Pipeline architecture (this repo's role)

This repo is the **single source of truth** for infrastructure: VMs,
containers, IPs, ports, and firewall rules.

> **Standing policy**: Nautobot is the system of record for infrastructure
> inventory — device identity, hardware, interfaces and MAC addresses, IP
> addresses and their DNS names, rack/power topology, and location. Every
> other system reads from it, keeping no second copy. **Direction, not
> current behaviour**: nothing reads from Nautobot yet, so the flow below is
> still what runs. Never add a *new* copy of a fact Nautobot models.

Full architecture — the planned Nautobot authority flip, downstream repo
relationships, inventory publish/sync flow — moved to
[docs/PIPELINE_ARCHITECTURE.md](docs/PIPELINE_ARCHITECTURE.md) to keep this
file under the shared 12 KB file-size gate.

## Development workflow

Static checks (`tofu fmt -check`, `tofu validate`, `tofu test`, module
suites) run automatically in pre-commit and CI — no manual step needed.
Credentialed ops (`tofu plan` against the live state backend) run
interactively before an apply; the apply itself is a Terrakube job (above)
— don't gate commits on either.

> **Never apply a targeted (`-target=...`) plan** — a partial apply still
> runs the inventory publish with an incomplete `ansible_inventory`,
> overwriting the full artifact all three consumer repos read. Always apply
> the whole plan.

Test in isolated pools, not production; use feature branches;
conventional-commit subjects only.

For slow operations and "context deadline exceeded" debugging:
[`TROUBLESHOOTING.md`](./TROUBLESHOOTING.md).

### Ansible

- Lint with `ansible-lint` before committing.
- Ensure idempotency (running twice produces no changes).
- Use FQCN (`ansible.builtin.apt`).

## Best practices

- Modular resource definitions; document variables with descriptions +
  validation; mark secrets `sensitive = true`.
- **Never use a `check` block for a load-bearing assertion** — a failed
  check only warns (plan exits 0, verified on OpenTofu 1.11); the guard
  looks present but does nothing. Use pre/postconditions or variable
  `validation` — `check` is advisory only. Rationale:
  `modules/proxmox-stack/checks.tf`.
- Terrakube state encrypted and restricted to workspace-scoped identities.
- Never update VMs directly; use OpenTofu or Ansible.
- Ansible: roles under `ansible/roles/` with Molecule tests; collections
  pinned in `ansible/requirements.yml`; config in `ansible/.ansible-lint`
  (profile: production).
- Never commit secrets, API tokens, or passwords — real infrastructure
  values live in a separate private repo; this repo holds placeholders only.

## File references

| Need | Location |
| --- | --- |
| Architecture (canonical) | [`docs/ARCHITECTURE.md`](./docs/ARCHITECTURE.md) |
| Dashboards + Hermes UIs (clean-URL contract) | [`docs/DASHBOARDS.md`](./docs/DASHBOARDS.md) |
| Network-quality monitoring (SmokePing) | [`docs/SMOKEPING.md`](./docs/SMOKEPING.md) |
| Honeypots / deception fabric + phone alerting | [`docs/HONEYPOTS.md`](./docs/HONEYPOTS.md) |
| Per-WAN diagnosis (modem/WAN telemetry) | [`docs/NETWORK_DIAGNOSIS.md`](./docs/NETWORK_DIAGNOSIS.md) |
| Troubleshooting + timeout/debug logging | [`TROUBLESHOOTING.md`](./TROUBLESHOOTING.md) |
| General docs | [`README.md`](./README.md) |
| Planning | GitHub Issues |
| Change history | PR descriptions + commits |
| Ansible config | `ansible/.ansible-lint` |
| Molecule tests | `ansible/roles/*/molecule/` |
| CI workflows | `.github/workflows/` |

## Ansible inventory output

`ansible_inventory` provides structured data for downstream Ansible.
Assembled in `local.ansible_inventory` (`inventory_publish.tf`); shared by
the `ansible_inventory` output (`outputs.tf`, one-line passthrough) and the
native `aws_s3_object` publish resource:

```hcl
local.ansible_inventory = {
  containers = { ... }
  vms = { ... }
  docker_vms = { ... }
  splunk_vm = { splunk = { vmid = 200, hostname = "splunk-aio", ip = "<derived>" } }
  constants = local.pipeline_constants
  ingress = { ... }
  host_services = var.host_services
  nodes = { ... }
  node_storage = { ... }
  domain = var.domain
}
```

## When to ask for clarification

Stop and ask before proceeding when: tool versions are unclear, multiple
valid approaches exist, changes affect production infrastructure, security
implications are uncertain, or breaking changes may be introduced.

## PR review checklist

- [ ] No exposed secrets or credentials.
- [ ] Variables documented; `sensitive = true` where appropriate.
- [ ] `tofu validate` passes.
- [ ] `ansible-lint` passes (if Ansible touched).
- [ ] Conventional commit message.
- [ ] Documentation updated where needed.
