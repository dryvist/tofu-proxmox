# =============================================================================
# iDRAC KVM container firewall configuration
# =============================================================================
# Extracted into its own file (like s3_rules.tf) so container_rules.tf
# stays under the shared _file-size workflow's 12 KB error threshold.
# The idrac-kvm host is a Docker-in-LXC (vm_id 251, tag "idrac"); it exposes the
# HTML5 noVNC viewers on host ports 5410 (R410) / 5710 (R710) via the
# idrac_kvm_svc security group (see security_groups.tf + locals.tf).

resource "proxmox_virtual_environment_firewall_options" "idrac_kvm" {
  for_each = var.idrac_kvm_container_ids

  node_name     = var.node_name
  container_id  = each.value
  enabled       = local.firewall_defaults.enabled
  input_policy  = local.firewall_defaults.input_policy
  output_policy = local.firewall_defaults.output_policy
  log_level_in  = local.firewall_defaults.log_level_in
  log_level_out = local.firewall_defaults.log_level_out

  depends_on = [proxmox_virtual_environment_cluster_firewall.main]
}

resource "proxmox_virtual_environment_firewall_rules" "idrac_kvm" {
  for_each = var.idrac_kvm_container_ids

  node_name    = var.node_name
  container_id = each.value

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.internal_access.name
    comment        = "Internal access (SSH, ICMP)"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.idrac_kvm_svc.name
    comment        = "iDRAC KVM HTML5 noVNC (TCP 5410, 5710)"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.outbound_internal.name
    comment        = "Outbound to internal only (covers iDRAC BMC egress on 443/5900)"
  }

  depends_on = [proxmox_virtual_environment_firewall_options.idrac_kvm]
}
