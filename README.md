# OpenTofu Proxmox Infrastructure

OpenTofu infrastructure for the Proxmox VE homelab: VMs, LXC containers,
resource pools, firewall rules, certificates, and the published Ansible
inventory.

Terrakube owns state, native workspace locking, execution, and audit history.
It exchanges workload identity for a short-lived OpenBao token. Providers then
read Proxmox, SSH, Route53, and RustFS credentials with native ephemeral
resources; no credential is stored in repository configuration or Terrakube
workspace variables.

## Installation

This repo is consumed by CI and Terrakube, not installed. For local static
checks, the Nix dev shell provides `tofu` via direnv:

```bash
direnv allow
```

## Usage

Static checks run locally without credentials; credentialed plans and
applies run remotely — see [How to apply / redeploy](#how-to-apply--redeploy)
below.

## Configuration

| Source | Contents |
| --- | --- |
| Private RustFS `deployment.json` | Desired state, topology, domain, and public SSH key |
| OpenBao `secret/infrastructure/proxmox` | Proxmox API and SSH credentials |
| OpenBao `secret/platform/object-storage` | RustFS endpoint and credentials |

Every apply publishes `ansible_inventory.json` back to RustFS through the
OpenTofu resource graph. Terrakube workspace locking replaces the former
backend-specific lock; no second global OpenBao lock is used.

## Local validation

The Nix dev shell activates through direnv. Local checks never require live
credentials:

```bash
direnv allow
tofu fmt -check -recursive
tofu init -backend=false
tofu validate
tofu test
tofu -chdir=modules/proxmox-stack init -backend=false
tofu -chdir=modules/proxmox-stack test
```

Credentialed plans, applies, imports, and state operations run only in the
private `tofu-proxmox` Terrakube workspace.

## How to apply / redeploy

Authenticate once per machine, then plan like any other `tofu` command — the run
executes remotely on a Terrakube executor, so no local Proxmox, AWS, or GitHub
credential is ever needed:

```bash
tofu login terrakube-api.<domain>   # one-time per machine
tofu init
tofu plan
```

**Applying is not a CLI step.** Every workspace sets `allowRemoteApply = false`,
so a CLI-driven apply is refused server-side regardless of who runs it. An apply
is a **Terrakube job**, started from the Terrakube UI or its API, and executed by
Terrakube itself — which is what puts every apply in the run audit, under the
workspace lock, and on the workspace's own OpenBao workload identity instead of
an operator's ambient shell.

Run the CLI half from a LAN execution host rather than a macOS workstation.
macOS Local Network privacy denies the ad-hoc-signed `tofu` binary, and the
symptom is a misleading `connect: no route to host` against a backend that is
in fact healthy.

Full runbook (access model, credential lifecycle, token scoping):
[docs.jacobpevans.com/infrastructure/applying-via-terrakube](https://docs.jacobpevans.com/infrastructure/applying-via-terrakube).

## Documentation

| Doc | Purpose |
| --- | --- |
| [docs/ARCHITECTURE.md](./docs/ARCHITECTURE.md) | Pipeline architecture and IP derivation |
| [docs/INVENTORY_PUBLISHING.md](./docs/INVENTORY_PUBLISHING.md) | Native RustFS inventory contract |
| [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) | Operational recovery guidance |

## License

Apache License 2.0 — see [LICENSE](LICENSE).
