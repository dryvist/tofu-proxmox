terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.113"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

# ACME Account - Let's Encrypt account registration.
# Prerequisite for certificate ordering.
resource "proxmox_acme_account" "accounts" {
  for_each = var.acme_accounts

  name      = each.key
  contact   = each.value.email
  directory = each.value.directory
  tos       = each.value.tos

  # Account ToS URL drifts as Let's Encrypt updates it; ignoring prevents
  # spurious diffs after creation.
  lifecycle {
    ignore_changes = [tos]
  }
}

# DNS Challenge Plugin - configures the DNS-01 challenge provider.
# `data` carries provider credentials and MUST come from private RustFS or OpenBao.
# Never write plaintext credentials to the repo.
resource "proxmox_acme_dns_plugin" "dns_plugins" {
  for_each = var.dns_plugins

  plugin = each.key
  api    = each.value.plugin_type
  data   = each.value.data
}

# ACME Certificate - the actual TLS certificate.
#
# Multi-domain: each cert covers `domain` (primary CN) plus all `sans`
# entries. Every domain in the list validates via DNS-01 using the same
# dns_plugin_id (DRY: single plugin per cert). The issued cert lands at
# /etc/pve/local/pveproxy-ssl.{pem,key} on `node_name`.
#
# Proxmox auto-renews certs ~30 days before expiry via
# pve-daily-update.service. Terraform manages the resource declaratively
# and respects Proxmox's renewal cadence.
resource "proxmox_acme_certificate" "certificates" {
  for_each = var.acme_certificates

  node_name = each.value.node_name
  account   = each.value.account_id

  domains = concat(
    [{ domain = each.value.domain, plugin = each.value.dns_plugin_id }],
    [for s in each.value.sans : { domain = s, plugin = each.value.dns_plugin_id }]
  )

  depends_on = [
    proxmox_acme_account.accounts,
    proxmox_acme_dns_plugin.dns_plugins
  ]
}

locals {
  # Flatten cert -> destinations into a list of delivery jobs, keyed by
  # "<cert_key>__<dest_index>" so the null_resource for_each can index it.
  cert_deliveries = merge([
    for cert_key, cert in var.acme_certificates : {
      for idx, dest in cert.destinations :
      "${cert_key}__${idx}" => {
        cert_key    = cert_key
        node_name   = cert.node_name
        kind        = dest.kind
        target_id   = dest.target_id
        target_ip   = coalesce(dest.target_ip, "")
        bundle_path = coalesce(dest.bundle_path, "")
        cert_path   = coalesce(dest.cert_path, "")
        key_path    = coalesce(dest.key_path, "")
        mode        = dest.mode
        owner       = dest.owner
        group       = dest.group
        reload_cmd  = dest.reload_cmd
      }
    }
  ]...)
}

# Cert delivery to LXCs/VMs.
#
# Connection: SSH to the Proxmox node (var.proxmox_ssh_*). The provisioner
# reads /etc/pve/local/pveproxy-ssl.{pem,key} (where Proxmox writes the
# node's cert, including auto-renewals) and pushes it to each destination
# via `pct push` (LXC) or `scp` (VM).
#
# Trigger model: re-runs when the cert's not_after timestamp or fingerprint
# changes (on renewal), when any destination shape changes, or when the
# reload command changes. The reload_cmd runs on every re-run.
#
# Bundle vs split mode:
#   - bundle_path: combined cert+key PEM (HAProxy, Caddy, nginx)
#   - cert_path + key_path: separate files (Splunk, Elasticsearch)
# Either or both can be set per destination.
resource "null_resource" "cert_delivery" {
  for_each = local.cert_deliveries

  triggers = {
    not_after   = proxmox_acme_certificate.certificates[each.value.cert_key].not_after
    fingerprint = proxmox_acme_certificate.certificates[each.value.cert_key].fingerprint
    target      = "${each.value.kind}:${each.value.target_id}:${each.value.target_ip}:${each.value.bundle_path}:${each.value.cert_path}:${each.value.key_path}:${each.value.mode}:${each.value.owner}:${each.value.group}"
    reload      = each.value.reload_cmd
  }

  connection {
    type        = "ssh"
    host        = var.proxmox_ssh_host
    user        = var.proxmox_ssh_username
    private_key = var.proxmox_ssh_private_key
  }

  provisioner "remote-exec" {
    inline = each.value.kind == "lxc" ? [
      "set -e",
      "umask 077",
      "TMPDIR=$(mktemp -d)",
      "trap 'rm -rf $TMPDIR' EXIT",
      each.value.bundle_path != "" ? "cat /etc/pve/local/pveproxy-ssl.pem /etc/pve/local/pveproxy-ssl.key > $TMPDIR/bundle.pem" : ":",
      each.value.cert_path != "" ? "cp /etc/pve/local/pveproxy-ssl.pem $TMPDIR/cert.pem" : ":",
      each.value.key_path != "" ? "cp /etc/pve/local/pveproxy-ssl.key $TMPDIR/key.pem" : ":",
      each.value.bundle_path != "" ? "pct exec ${each.value.target_id} -- mkdir -p $(dirname '${each.value.bundle_path}')" : ":",
      each.value.bundle_path != "" ? "pct push ${each.value.target_id} $TMPDIR/bundle.pem '${each.value.bundle_path}' --user ${each.value.owner} --group ${each.value.group} --perms ${each.value.mode}" : ":",
      each.value.cert_path != "" ? "pct exec ${each.value.target_id} -- mkdir -p $(dirname '${each.value.cert_path}')" : ":",
      each.value.cert_path != "" ? "pct push ${each.value.target_id} $TMPDIR/cert.pem '${each.value.cert_path}' --user ${each.value.owner} --group ${each.value.group} --perms ${each.value.mode}" : ":",
      each.value.key_path != "" ? "pct exec ${each.value.target_id} -- mkdir -p $(dirname '${each.value.key_path}')" : ":",
      each.value.key_path != "" ? "pct push ${each.value.target_id} $TMPDIR/key.pem '${each.value.key_path}' --user ${each.value.owner} --group ${each.value.group} --perms ${each.value.mode}" : ":",
      each.value.reload_cmd != "" ? "pct exec ${each.value.target_id} -- sh -c '${each.value.reload_cmd}'" : ":",
      ] : [
      "set -e",
      "umask 077",
      "TMPDIR=$(mktemp -d)",
      "trap 'rm -rf $TMPDIR' EXIT",
      each.value.bundle_path != "" ? "cat /etc/pve/local/pveproxy-ssl.pem /etc/pve/local/pveproxy-ssl.key > $TMPDIR/bundle.pem" : ":",
      each.value.cert_path != "" ? "cp /etc/pve/local/pveproxy-ssl.pem $TMPDIR/cert.pem" : ":",
      each.value.key_path != "" ? "cp /etc/pve/local/pveproxy-ssl.key $TMPDIR/key.pem" : ":",
      "SSH_OPTS='-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/root/.ssh/known_hosts'",
      each.value.bundle_path != "" ? "ssh $SSH_OPTS root@${each.value.target_ip} \"mkdir -p $(dirname '${each.value.bundle_path}')\"" : ":",
      each.value.bundle_path != "" ? "scp $SSH_OPTS $TMPDIR/bundle.pem root@${each.value.target_ip}:'${each.value.bundle_path}'" : ":",
      each.value.cert_path != "" ? "ssh $SSH_OPTS root@${each.value.target_ip} \"mkdir -p $(dirname '${each.value.cert_path}')\"" : ":",
      each.value.cert_path != "" ? "scp $SSH_OPTS $TMPDIR/cert.pem root@${each.value.target_ip}:'${each.value.cert_path}'" : ":",
      each.value.key_path != "" ? "ssh $SSH_OPTS root@${each.value.target_ip} \"mkdir -p $(dirname '${each.value.key_path}')\"" : ":",
      each.value.key_path != "" ? "scp $SSH_OPTS $TMPDIR/key.pem root@${each.value.target_ip}:'${each.value.key_path}'" : ":",
      each.value.bundle_path != "" ? "ssh $SSH_OPTS root@${each.value.target_ip} \"chmod ${each.value.mode} '${each.value.bundle_path}' && chown ${each.value.owner}:${each.value.group} '${each.value.bundle_path}'\"" : ":",
      each.value.cert_path != "" ? "ssh $SSH_OPTS root@${each.value.target_ip} \"chmod ${each.value.mode} '${each.value.cert_path}' && chown ${each.value.owner}:${each.value.group} '${each.value.cert_path}'\"" : ":",
      each.value.key_path != "" ? "ssh $SSH_OPTS root@${each.value.target_ip} \"chmod ${each.value.mode} '${each.value.key_path}' && chown ${each.value.owner}:${each.value.group} '${each.value.key_path}'\"" : ":",
      each.value.reload_cmd != "" ? "ssh $SSH_OPTS root@${each.value.target_ip} \"${each.value.reload_cmd}\"" : ":",
    ]
  }
}
