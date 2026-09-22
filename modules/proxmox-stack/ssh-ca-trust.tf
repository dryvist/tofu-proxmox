# Bakes OpenBao SSH-CA trust into new guests' cloud-init vendor-data, so a
# fresh guest is cert-reachable from birth (the SSH-CA trust ADR; sibling of
# ansible-proxmox-apps roles/ssh_ca_trust, which owns the SAME trust on an
# already-running guest post-boot, but only for the vms/splunk_vms/docker_vms
# groups — LXC containers are never in that role's play scope and get no
# CA trust from any mechanism today; this module is VM-only for the same
# reason cloud-init itself is VM-only, so that gap is unchanged by this).
# First-boot only: vendor-data is in modules/proxmox-vm's ignore_changes, so
# an existing guest never diffs or rebuilds its non-removable cloud-init
# drive from this.
#
# Read via the workspace's OWN authenticated OpenBao identity (vault
# provider, already configured in main.tf) against ssh-client-ca's
# config/ca endpoint — not the unauthenticated public_key endpoint the
# Ansible role uses. The channel itself is the trust boundary here (the
# workspace's JWT role must be granted read on this path — tracked
# separately, see the PR description), so no fingerprint pin is needed
# the way the Ansible role's TOFU-averse design requires for an
# unauthenticated fetch.
#
# Single-condition activation gate: at the default (rollout disabled) this
# whole file is a no-op — no data source evaluated, nothing rendered,
# nothing to plan.
locals {
  ssh_ca_trust_enabled = var.ssh_ca_trust_rollout_enabled

  # One snippet per NODE that actually hosts an opted-in VM — bpg's
  # proxmox_virtual_environment_file is node-scoped storage, so a single
  # shared file wouldn't be visible cluster-wide unless the datastore itself
  # is shared. Deriving the node set from var.vms keeps this to exactly the
  # nodes that need it, no placeholders for the rest of the cluster.
  ssh_ca_trust_nodes = local.ssh_ca_trust_enabled ? toset([
    for v in var.vms : v.node_name if v.ssh_ca_trust
  ]) : []

  # Guarded by the SAME condition as the data source's own count, which
  # Terraform's graph evaluator special-cases: the false branch is never
  # forced to index into an empty collection. Without this guard the
  # templatefile call is evaluated unconditionally regardless of how many
  # nodes need it, and errors on `data.http...[0]` the moment the feature
  # is off — caught by a plan against this exact default.
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
