# OpenBao and Terrakube Secret Contract

OpenBao is the only machine secret manager for these OpenTofu workspaces.
Terrakube is the execution, state, locking, and audit plane. Both services run
inside the homelab and routine operation requires no public internet.

## Four-tier hierarchy (end-state)

| Tier | System | Role | AI / machine access |
| --- | --- | --- | --- |
| **T1** | SOPS + age | Git-committed encrypted deployment config (not credentials) | Read at plan/apply via the age key |
| **T2** | OpenBao | **Primary machine + AI runtime secrets engine**: dynamic secrets, rotation, and workspace credentials | Yes — via least-privilege AppRoles |
| **T3** | Doppler | Strict cloud tier: OpenBao secret-zero + rare user-approved keys-to-kingdom | Only for rare, explicitly user-approved operations |
| **T4** | Bitwarden | Human-only vault | **Never** |

## AI agent and operator credential chain

The `.envrc` in each consumer repo uses an OpenBao AppRole to pull
non-secret backend coordinates at `direnv allow`:

```text
Doppler T3 → BAO_ADDR + AppRole creds (role_id / secret_id)
    ↓  (operator's shell / AI agent session)
OpenBao AppRole login
    ↓
secret/platform/terrakube/main
    → TF_CLOUD_HOSTNAME, TF_CLOUD_ORGANIZATION  (passed to cloud {} block)
    ↓
tofu init / tofu plan / tofu apply
    (authenticates via ~/.terraform.d/credentials.tfrc.json from human tofu login)
```

## Authentication

Terrakube signs a per-job workload token. OpenBao validates its issuer,
audience, workspace, organization, and project claims, then returns a
short-lived token bound to the exact workspace policy. Long-lived AppRole
secrets and provider credentials are not stored in Terrakube.

## Native paths

| Path | Consumer | Contents |
| --- | --- | --- |
| `secret/infrastructure/proxmox` | `tofu-proxmox` (remote executor) | Proxmox API, PVE SSH, and VM SSH credentials |
| `secret/platform/object-storage` | infrastructure workspaces | RustFS endpoint and credentials |
| `secret/platform/terrakube/main` | operator shell / AI agent `.envrc` | `TF_CLOUD_HOSTNAME`, `TF_CLOUD_ORGANIZATION` |
| `aws/creds/tf-proxmox` | `tofu-proxmox-aws-infra` | Dynamic Route53 STS credentials |
| `secret/apps/media` | `tofu-proxmox-servarr-config` | Sonarr/Radarr endpoints and API keys |
| `secret/infrastructure/proxmox-packer` | approved Packer operator | Packer-only Proxmox and Splunk fields |

Use provider-native ephemeral resources whenever the destination accepts an
ephemeral value. If a provider persists a secret-bearing resource argument and
offers no write-only field, transfer that feature to Ansible or restrict and
encrypt Terrakube state until the provider adds native support.

The private RustFS `deployment.json` holds desired state only. It may contain
network topology and public keys, but never tokens, passwords, or private keys.

## Third-party SaaS credentials (`secrets-external/` mount)

Third-party SaaS credentials have a different security posture than
homelab-internal machine credentials, so they live under their own top-level
OpenBao KV mount rather than nesting under `secret/platform/...`:

| Mount | Holds |
| --- | --- |
| `secret/` | Homelab-internal machine/service credentials (existing, unchanged). |
| `secrets-external/` | Third-party SaaS API keys/credentials, least-privilege-scoped per consumer the same way `secret/` is. |

**The mount has no consumer yet.** This section previously listed the Backblaze
B2 credential as its first path. That was aspirational, and following it cost
real time: capability checks against `secrets-external/backblaze-b2` return
**deny** for every role reachable from the converge environment, and a deny
cannot be told apart from an absent path.

The credential in use today lives at `secret/platform/backblaze`, readable by
the Ansible role, with fields `B2_S3_ENDPOINT`, `B2_BACKUPS_BUCKET`,
`B2_BACKUPS_KEY_ID`, and `B2_BACKUPS_APP_KEY`. It is consumed by
`ansible-splunk` for the Splunk frozen (archival) tier — **not** by this repo
or Terrakube. No workspace role here reads `secrets-external/`.

When a genuine first consumer appears, add it to a table here. Until then this
mount is a convention, not a location anything resolves.

> Enabling the new `secrets-external/` KV v2 engine and writing its first policy
> is a **human-admin OpenBao action**. No dedicated secrets-platform Terraform
> repo exists in this workspace to automate it, and per this org's admin
> write-gate convention machine identities do not provision new mounts or
> policies. This document describes the convention; it does not provision the
> mount.

## Locking

Terrakube workspace locking serializes OpenTofu runs. OpenBao does not provide
a second global flow lock for these workspaces.
