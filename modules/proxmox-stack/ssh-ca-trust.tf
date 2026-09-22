# Bakes OpenBao SSH-CA trust into every new guest's cloud-init vendor-data.
# vendor_data_file_id is in modules/proxmox-vm's ignore_changes, so this
# never diffs or rebuilds an existing guest's cloud-init drive.
#
# Reads the CA public key via the workspace's own authenticated OpenBao
# identity (vault_generic_secret against ssh-client-ca/config/ca).
#
# At the default (rollout disabled) this file is a no-op — no data source
# evaluated, nothing rendered, nothing to plan.
locals {
  ssh_ca_trust_enabled = var.ssh_ca_trust_rollout_enabled

  # One snippet per node — bpg's file resource is node-scoped storage.
  ssh_ca_trust_nodes = local.ssh_ca_trust_enabled ? toset([
    for v in var.vms : v.node_name
  ]) : []

  # Guarded by the same condition as the data source's own count, so the
  # false branch never indexes into an empty result.
  ssh_ca_trust_vendor_data = local.ssh_ca_trust_enabled ? templatefile("${path.module}/templates/ssh-ca-trust-vendor-data.yml.tpl", {
    ca_public_key  = trimspace(data.vault_generic_secret.ssh_ca_config[0].data["public_key"])
    principals_dir = "/etc/ssh/principals"
    ca_file        = "/etc/ssh/trusted-user-ca-keys.pem"
    sshd_dropin    = "/etc/ssh/sshd_config.d/99-openbao-ca.conf"
  }) : null

  ssh_ca_vendor_data_file_ids = {
    for node in local.ssh_ca_trust_nodes :
    node => proxmox_virtual_environment_file.ssh_ca_trust_vendor_data[node].id
  }
}

data "vault_generic_secret" "ssh_ca_config" {
  count = local.ssh_ca_trust_enabled ? 1 : 0
  path  = "${var.ssh_ca_trust_mount}/config/ca"
}

resource "proxmox_virtual_environment_file" "ssh_ca_trust_vendor_data" {
  for_each = local.ssh_ca_trust_nodes

  content_type = "snippets"
  datastore_id = var.ssh_ca_trust_snippets_datastore_id
  node_name    = each.value

  source_raw {
    data      = local.ssh_ca_trust_vendor_data
    file_name = "ssh-ca-trust-vendor-data.yml"
  }
}
