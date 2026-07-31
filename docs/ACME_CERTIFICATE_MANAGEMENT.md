# ACME Certificate Management

Operational guide for managing Let's Encrypt TLS certificates on Proxmox VE using
Terraform and AWS Route53 DNS-01 challenge validation.

For module-level reference (variables, outputs, usage examples), see
[`modules/acme-certificate/README.md`](../modules/acme-certificate/README.md).

---

## Architecture Overview

```text
Terraform (local) ──► BPG Proxmox Provider ──► Proxmox VE API
                                                     │
                              Route53 DNS-01 ◄────── pve-daily-update.service
                                    │                     (auto-renewal)
                              Let's Encrypt
```

### Components

| Component | Role |
| --- | --- |
| `modules/acme-certificate/` | Terraform module managing accounts, DNS plugins, certificates |
| BPG Proxmox provider | Translates Terraform HCL into Proxmox API calls |
| AWS Route53 | DNS-01 challenge: creates `_acme-challenge` TXT records |
| `pve-daily-update.service` | Proxmox systemd service that renews certificates 30 days before expiry |
| OpenBao | Injects Route53 IAM credentials at deploy time and stores them in Proxmox |

### Secret Flow

**Initial provisioning (Terrakube apply run):**

1. Apply via a Terrakube job (plan remotely, confirm the run in the workspace UI — a CLI `tofu apply` is refused server-side)
2. OpenBao injects `ROUTE53_ACCESS_KEY`, `ROUTE53_SECRET_KEY`, `ROUTE53_ZONE_ID`, `ACME_EMAIL`, `ACME_DOMAIN`
3. Terraform configures the BPG Proxmox DNS plugin via API
4. Proxmox stores credentials in `/etc/pve/priv/acme/plugins.cfg` (encrypted cluster filesystem)

**Automatic renewal (no OpenBao required):**

1. `pve-daily-update.service` runs daily
2. Proxmox reads credentials from `/etc/pve/priv/acme/plugins.cfg`
3. Creates DNS TXT record in Route53, validates with Let's Encrypt, installs renewed certificate

---

## Configuration Guide

### OpenBao Secrets

Before applying, configure the following secrets in OpenBao:

| Secret | Description |
| --- | --- |
| `ROUTE53_ACCESS_KEY` | AWS IAM access key with Route53 permissions |
| `ROUTE53_SECRET_KEY` | AWS IAM secret key |
| `ROUTE53_ZONE_ID` | Route53 hosted zone ID for the target domain |
| `ACME_EMAIL` | Email address for Let's Encrypt account notifications |
| `ACME_DOMAIN` | FQDN for the certificate (e.g., `proxmox-1.example.com`) |

Minimum required IAM policy for Route53:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "route53:GetChange",
        "route53:GetHostedZone",
        "route53:ChangeResourceRecordSets",
        "route53:ListResourceRecordSets"
      ],
      "Resource": [
        "arn:aws:route53:::hostedzone/<ZONE_ID>",
        "arn:aws:route53:::change/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": "route53:ListHostedZones",
      "Resource": "*"
    }
  ]
}
```

### Terraform Variables (`terraform.tfvars`)

The OpenBao secrets named `ROUTE53_ACCESS_KEY` / `ROUTE53_SECRET_KEY` are mapped to
the standard `AWS_*` keys that the BPG Proxmox provider expects via the
[OpenBao config name-transformer](https://docs.OpenBao.com/docs/cli-name-transformers)
configured for this project. The Terraform variable `dns_plugins` then references
those (now-canonically-named) secrets via the `TF_VAR_dns_plugins` env var that
the Terrakube run injects — `terraform.tfvars` itself does not
read environment variables.

```hcl
acme_accounts = {
  "letsencrypt" = {
    email     = "admin@example.com"
    directory = "https://acme-v02.api.letsencrypt.org/directory"
    tos       = "https://letsencrypt.org/documents/LE-SA-v1.4-April-3-2024.pdf"
  }
}

# dns_plugins is provided by OpenBao as TF_VAR_dns_plugins (JSON), NOT in terraform.tfvars.
# Example shape (do not commit literal credentials):
#
# dns_plugins = {
#   "myroute53" = {
#     plugin_type = "route53"
#     data = {
#       "AWS_ACCESS_KEY_ID"     = "<from OpenBao ROUTE53_ACCESS_KEY>"
#       "AWS_SECRET_ACCESS_KEY" = "<from OpenBao ROUTE53_SECRET_KEY>"
#       "AWS_DEFAULT_REGION"    = "us-east-1"
#     }
#   }
# }

acme_certificates = {
  "proxmox-1-cert" = {
    node_name     = "proxmox-1"
    domain        = "proxmox-1.example.com"
    account_id    = "letsencrypt"
    dns_plugin_id = "myroute53"
  }
}
```

Use the Let's Encrypt staging directory (`https://acme-staging-v02.api.letsencrypt.org/directory`) for
testing to avoid production rate limits.

### Applying

Plan remotely (`tofu plan` streams from the Terrakube executor), then confirm
the apply as a Terrakube job in the workspace UI — a CLI `tofu apply` is
refused server-side (`allowRemoteApply = false`).

---

## Renewal Procedures

### Automatic Renewal

Proxmox renews certificates automatically 30 days before expiry via `pve-daily-update.service`.
No manual action is required as long as:

- Proxmox can reach Let's Encrypt and AWS Route53
- Credentials in `/etc/pve/priv/acme/plugins.cfg` are valid

Monitor the renewal timer:

```bash
# Check timer status
systemctl status pve-daily-update.timer

# Review recent renewal attempts
journalctl -u pve-daily-update.service --since "7 days ago"

# Check certificate expiry
pvenode acme cert list
```

### Manual Renewal

Force certificate renewal outside the automatic schedule:

```bash
# Renew via Proxmox CLI
pvenode acme cert order

# Or via Proxmox web UI: Datacenter → node → Certificates → Order Certificate
```

### Rotation After Credential Change

If Route53 IAM credentials are rotated:

1. Update secrets in OpenBao

2. Re-apply to push new credentials to Proxmox: plan remotely, then confirm
   the run as a Terrakube job in the workspace UI.

3. Verify Proxmox has the updated credentials:

   ```bash
   # Confirm the node references the right ACME account + domains
   pvesh get /nodes/proxmox-1/config --output-format=json | jq '.acme'

   # Verify the DNS plugin (cluster-wide resource — credentials are masked)
   pvesh get /cluster/acme/plugins/myroute53 --output-format=json
   ```

---

## Importing Existing Certificates

If ACME resources were created manually in Proxmox before Terraform management was added:

```bash
# Note: the `acme_certificates` module is declared with `count = length(...) > 0 ? 1 : 0`,
# so the resource addresses include the `[0]` index.

# Import ACME account
tofu import \
  'module.acme_certificates[0].proxmox_virtual_environment_acme_account.accounts["letsencrypt"]' \
  'letsencrypt'

# Import DNS plugin
tofu import \
  'module.acme_certificates[0].proxmox_virtual_environment_acme_dns_plugin.dns_plugins["myroute53"]' \
  'myroute53'

# Import certificate (node name as the ID)
tofu import \
  'module.acme_certificates[0].proxmox_virtual_environment_acme_certificate.certificates["proxmox-1-cert"]' \
  'proxmox-1'
```

After import, run `terraform plan` and verify zero drift. If the plan shows changes, align
`terraform.tfvars` values to match what Proxmox reports.

---

## Troubleshooting

### DNS validation fails during certificate order

**Symptoms:** the Terrakube apply run fails with an ACME DNS-01 challenge error; Let's Encrypt reports
it cannot find the `_acme-challenge` TXT record.

**Checks:**

1. Verify Route53 IAM credentials in OpenBao are valid
2. Confirm IAM policy includes `route53:ChangeResourceRecordSets` and `route53:GetChange`

3. Check DNS propagation:

   ```bash
   dig -t TXT _acme-challenge.proxmox-1.example.com @8.8.8.8
   ```

4. Review Proxmox certificate logs:

   ```bash
   journalctl -u pve-daily-update.service -n 50
   ```

### Certificate renewal fails silently

**Symptoms:** Certificate approaches expiry; no renewal in logs; `pve-daily-update.service` shows errors.

**Checks:**

1. Check if Proxmox can reach Let's Encrypt:

   ```bash
   curl -I https://acme-v02.api.letsencrypt.org/directory
   ```

2. Verify Route53 credentials have not expired:

   Re-apply to refresh credentials: plan remotely, then confirm the run as a
   Terrakube job in the workspace UI.

3. Confirm `pveproxy` is running:

   ```bash
   systemctl status pveproxy
   ```

### `terraform plan` shows unexpected drift after import

**Symptoms:** After `terraform import`, plan shows changes to imported resources.

**Checks:**

1. Inspect imported state:

   ```bash
   tofu state show \
     'module.acme_certificates[0].proxmox_virtual_environment_acme_account.accounts["letsencrypt"]'
   ```

2. Compare `email` and `directory` values against `terraform.tfvars`
3. Update `terraform.tfvars` to match current Proxmox state, then re-plan

### Rate limit errors from Let's Encrypt

**Symptoms:** Certificate order fails with "too many certificates already issued".

**Resolution:** Use the staging directory for testing:

```hcl
acme_accounts = {
  "letsencrypt-staging" = {
    directory = "https://acme-staging-v02.api.letsencrypt.org/directory"
    ...
  }
}
```

Switch back to production once testing is complete.

### Certificate hostname mismatch

**Symptoms:** Browser shows a certificate error for the wrong hostname (e.g.,
`CN=proxmox-1.mgmt` when accessing `proxmox-1.example.com`) — the certificate was
generated with an old hostname configuration.

**Checks:**

1. Verify the hostname configuration:

   ```bash
   hostname -f     # Should show the FQDN
   cat /etc/hosts  # Should map the IP to the FQDN
   ```

2. Regenerate the self-signed cert (if not using ACME):

   ```bash
   pvecm updatecerts --force
   systemctl restart pveproxy
   ```

3. Or order a new ACME cert:

   ```bash
   pvenode acme cert order --force
   ```

### Duplicate domain in ACME config

**Symptoms:** `duplicate domain 'example.com' in ACME config properties 'acmedomain0' and 'acme'`.

**Resolution:** Remove the simple `acme:` line and keep only the `acmedomain0:`
entry that names the DNS plugin:

```ini
# Wrong — causes a duplicate
acme: domains=example.com
acmedomain0: example.com,plugin=AWS

# Correct — single entry with plugin
acmedomain0: example.com,plugin=AWS
```

---

## Wildcard Certificates

Proxmox VE does not natively support wildcard certificates (`*.example.com`) as of
version 9.1 — tracked in [Proxmox Bugzilla #5719](https://bugzilla.proxmox.com/show_bug.cgi?id=5719).

Workarounds:

1. Issue a specific certificate per subdomain.
2. Use external tooling (`acme.sh`, `certbot`) and install the certificate manually.
3. Terminate TLS at a reverse proxy that holds a wildcard certificate in front of Proxmox.

---

## References

- [`modules/acme-certificate/README.md`](../modules/acme-certificate/README.md) — module variables, outputs, and usage examples
- [BPG Proxmox Provider — ACME resources](https://registry.terraform.io/providers/bpg/proxmox/latest/docs)
- [Proxmox Certificate Management](https://pve.proxmox.com/wiki/Certificate_Management)
- [Let's Encrypt Documentation](https://letsencrypt.org/docs/)
- [Let's Encrypt Rate Limits](https://letsencrypt.org/docs/rate-limits/)
- [Route53 DNS-01 Challenge](https://letsencrypt.org/docs/challenge-types/#dns-01-challenge)
- [Route53 — Working with DNS records](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/rrsets-working-with.html)
