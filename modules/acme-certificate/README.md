# ACME Certificate Module

Manages Let's Encrypt certificates for Proxmox VE nodes (via the BPG provider) and optionally
delivers the issued certs to LXCs and VMs for use by services like HAProxy and Splunk.

## What this module owns

- **`proxmox_acme_account`** — Let's Encrypt account registration.
- **`proxmox_acme_dns_plugin`** — DNS-01 challenge provider config (credentials carried in `data`).
- **`proxmox_acme_certificate`** — the per-node cert resource. Supports a primary domain + SANs.
- **`null_resource.cert_delivery`** — pushes the issued cert to LXC/VM destinations via SSH to the
  Proxmox node, using `pct push` (LXC) or `scp` (VM).

The module does **not** manage Route53 hosted zones (see `aws-infra/` for that).

## Requirements

- Proxmox VE node with cluster-level ACME support (PVE 7.x+).
- BPG Proxmox provider `~> 0.106`, hashicorp/null `~> 3.2`.
- A reachable ACME directory (Let's Encrypt prod or staging).
- A DNS-01 challenge provider (this repo uses AWS Route53; credentials must live in private RustFS or
  OpenBao, never plaintext).
- SSH access from the Terraform-runner host to the Proxmox node (`var.proxmox_ssh_host`,
  `var.proxmox_user`, `var.proxmox_ssh_private_key`).
- For VM delivery destinations: SSH access from the Proxmox node to each VM's `target_ip` as
  `root` (cloud-init sets this up via the `vm-access-key` injected at template build time).

## Usage

```hcl
module "acme_certificates" {
  source = "./modules/acme-certificate"

  acme_accounts = {
    default = {
      email     = "you@example.com"
      directory = "https://acme-v02.api.letsencrypt.org/directory"
      tos       = "https://letsencrypt.org/documents/LE-SA-v1.5-February-24-2025.pdf"
    }
  }

  dns_plugins = {
    AWS = {
      plugin_type = "aws"
      data = {
        AWS_ACCESS_KEY_ID     = "<from private RustFS>"
        AWS_SECRET_ACCESS_KEY = "<from private RustFS>"
      }
    }
  }

  acme_certificates = {
    proxmox-1 = {
      node_name     = "proxmox-1"
      domain        = "proxmox-1.example.com"
      account_id    = "default"
      dns_plugin_id = "AWS"
      sans = [
        "infisical.example.com",
        "splunk.example.com",
      ]
      destinations = [
        {
          kind        = "lxc"
          target_id   = 175
          bundle_path = "/etc/ssl/private/haproxy.pem"
          reload_cmd  = "systemctl reload haproxy"
        },
        {
          kind       = "vm"
          target_id  = 200
          target_ip  = "192.168.20.200"
          cert_path  = "/opt/splunk/etc/auth/server.pem"
          key_path   = "/opt/splunk/etc/auth/server.key"
          owner      = "splunk"
          group      = "splunk"
          reload_cmd = "/opt/splunk/bin/splunk restart splunkweb"
        },
      ]
    }
  }

  proxmox_ssh_host        = var.proxmox_ssh_host
  proxmox_user            = var.proxmox_user
  proxmox_ssh_private_key = var.proxmox_ssh_private_key
  environment             = "homelab"
}
```

## Schema

### `acme_accounts`

Same shape as before. `directory` is the LE production or staging URL; `tos` is the current
ToS URL (drift on `tos` is ignored via lifecycle).

### `dns_plugins`

`data` is a free-form map carrying provider credentials. For Route53:
`{ AWS_ACCESS_KEY_ID = "...", AWS_SECRET_ACCESS_KEY = "..." }`. Must come from private RustFS/OpenBao.

### `acme_certificates`

Each entry produces one `proxmox_acme_certificate` covering `domain` (CN) plus all `sans` (each
validated through the same `dns_plugin_id`). Optional `destinations` list configures cert
delivery to LXCs/VMs after issuance.

#### Destination fields

| Field | Required | Notes |
| --- | --- | --- |
| `kind` | yes | `"lxc"` or `"vm"` |
| `target_id` | yes | vm_id of the LXC or VM |
| `target_ip` | when kind = `"vm"` | SSH host for `scp` (Proxmox node SSHes to this IP) |
| `bundle_path` | one of... | Combined cert+key PEM (HAProxy, Caddy, nginx) |
| `cert_path` | ...these... | Cert+chain PEM only (Splunk, Elasticsearch) |
| `key_path` | ...combos | Private key (required alongside `cert_path`) |
| `mode` | optional | File mode, default `0600` |
| `owner` | optional | File owner, default `root` |
| `group` | optional | File group, default `root` |
| `reload_cmd` | optional | Command run on the target after delivery; runs on every re-trigger |

Validation: each destination must set **either** `bundle_path` **or** both `cert_path` and
`key_path`. VMs additionally require `target_ip`.

### `proxmox_ssh_host` / `proxmox_user` / `proxmox_ssh_private_key`

SSH credentials for the cert-delivery null_resource. `proxmox_ssh_host` and
`proxmox_ssh_private_key` are sourced from OpenBao (`PROXMOX_VE_HOSTNAME`,
`PROXMOX_SSH_PRIVATE_KEY`); `proxmox_user` comes from the desired state
(`deployment.json`'s `proxmox_user` key) — it is config, not a secret. Both
thread through `native root configuration` → root `main.tf`.

## Delivery model

The Proxmox node is the source of truth for the issued cert
(`/etc/pve/local/pveproxy-ssl.{pem,key}`). When `proxmox_acme_certificate` renews (Proxmox does
this automatically ~30 days before expiry via `pve-daily-update.service`), the cert's
`not_after` and `fingerprint` attributes change. The `null_resource.cert_delivery` triggers on
those changes and re-pushes the cert to every destination, then runs each `reload_cmd`.

For **LXC** destinations:

1. SSH to the Proxmox node.
2. Build the bundle (`cat pveproxy-ssl.pem pveproxy-ssl.key`) and/or split files in a per-job tmpdir.
3. `pct exec` to ensure target directories exist.
4. `pct push` the file(s) with `--user 0 --group 0 --perms <mode>`.
5. `pct exec` the `reload_cmd` if set.

For **VM** destinations:

1. SSH to the Proxmox node.
2. Build the bundle/split files in a per-job tmpdir.
3. SSH from the Proxmox node to the VM's `target_ip` to create target directories.
4. `scp` the file(s) from the Proxmox node to the VM.
5. SSH to set `chmod`/`chown`.
6. SSH to run the `reload_cmd` if set.

## Importing existing resources

If your Proxmox node already has a manually-configured ACME account, plugin, and certificate,
import them before the first `apply`:

```bash
cd <repo>/main

# 1. Account — name from `pvesh get /cluster/acme/account` (default in homelab is "default")
tofu import \
  'module.acme_certificates[0].proxmox_acme_account.accounts["default"]' \
  'default'

# 2. DNS plugin — name from `pvesh get /cluster/acme/plugins`
tofu import \
  'module.acme_certificates[0].proxmox_acme_dns_plugin.dns_plugins["AWS"]' \
  'AWS'

# 3. Certificate — ID is the node name
tofu import \
  'module.acme_certificates[0].proxmox_acme_certificate.certificates["proxmox-1"]' \
  'proxmox-1'
```

After import, run `tofu plan`. Expected diff:

- **Account**: zero changes (assuming HCL email/directory/tos match).
- **DNS plugin**: zero changes if HCL `data` matches what's stored in PVE. Update private RustFS to match
  if there's drift.
- **Certificate**: drift on `domains` if you're adding SANs in HCL that weren't on the live
  cert. Apply triggers re-issuance with the new SAN list.

`null_resource.cert_delivery` is not importable; the first apply pushes the cert to every
configured destination.

## Outputs

| Output | Sensitive | Notes |
| --- | --- | --- |
| `acme_accounts` | no | Map of `{id, email}` per account |
| `dns_plugins` | yes | Map of `{id, plugin}` per plugin |
| `certificates` | no | Map of `{node_name, account, domains, not_after, issuer, subject}` |
| `cert_deliveries` | no | Map of `{cert_key, kind, target_id, target_ip, bundle_path, cert_path, key_path}` per delivery job |

## Renewal monitoring

```bash
ssh root@<pve-host> 'systemctl status pve-daily-update.timer'
ssh root@<pve-host> 'journalctl -u pve-daily-update.service --since "7 days ago"'
# Manual order:
ssh root@<pve-host> 'pvenode acme cert order'
```

When Proxmox renews, the next `tofu apply` (or any plan that refreshes the `null_resource`
triggers) will re-push the cert to every destination automatically.

## Troubleshooting

| Symptom | Likely cause |
| --- | --- |
| Plan wants to recreate the account | `tos` or `directory` mismatch — update private RustFS to match the live account |
| Plan wants to recreate the DNS plugin | `data` map drift (AWS key rotated outside Terraform) — update private RustFS |
| Cert order fails with DNS validation | Route53 IAM perms insufficient, or wrong zone; check `journalctl -u pveproxy` |
| `pct push` fails with "no such file" | Target directory doesn't exist — module auto-`mkdir -p`s but check the path |
| `scp` to VM fails with auth error | PVE node lacks SSH access to the VM as `root`; check `~/.ssh/authorized_keys` |
| `reload_cmd` fails but cert is delivered | Command syntax issue — run it manually on the target to debug |

## References

- [BPG Proxmox Provider — proxmox_acme_certificate](https://registry.terraform.io/providers/bpg/proxmox/latest/docs/resources/acme_certificate)
- [Proxmox Wiki — Certificate Management](https://pve.proxmox.com/wiki/Certificate_Management)
- [Let's Encrypt — ACME v2 directory](https://letsencrypt.org/docs/)
