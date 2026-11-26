# =============================================================================
# VM Firewall Configuration
# =============================================================================

resource "proxmox_virtual_environment_firewall_options" "splunk_vm" {
  for_each = var.splunk_vm_ids

  node_name     = lookup(var.splunk_vm_nodes, each.key, coalesce(var.splunk_node_name, var.node_name))
  vm_id         = each.value
  enabled       = local.firewall_defaults.enabled
  input_policy  = local.firewall_defaults.input_policy
  output_policy = local.firewall_defaults.output_policy
  log_level_in  = local.firewall_defaults.log_level_in
  log_level_out = local.firewall_defaults.log_level_out

  depends_on = [proxmox_virtual_environment_cluster_firewall.main]
}

resource "proxmox_virtual_environment_firewall_rules" "splunk_vm" {
  for_each = var.splunk_vm_ids

  node_name = lookup(var.splunk_vm_nodes, each.key, coalesce(var.splunk_node_name, var.node_name))
  vm_id     = each.value

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.internal_access.name
    comment        = "Internal access (SSH, ICMP)"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.splunk_services.name
    comment        = "Splunk services (Web, HEC, Forwarding)"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.syslog.name
    comment        = "Syslog ingestion"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.splunk_cluster.name
    comment        = "Splunk cluster communication"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.outbound_internal.name
    comment        = "Outbound to internal only"
  }

  depends_on = [proxmox_virtual_environment_firewall_options.splunk_vm]
}

# T-Pot deep-sensor VM. T-Pot deliberately exposes 20+ honeypot ports and runs
# its own dockerized firewall; enumerating that surface in Proxmox would be
# brittle and self-defeating, so input is permissive-but-logged. Egress is the
# real control: DROP by default with outbound limited to internal (reach the
# apprise gateway + HAProxy syslog 519) plus HTTPS (image/update + threat-intel
# pulls) — captured malware cannot beacon to arbitrary destinations.

resource "proxmox_virtual_environment_firewall_options" "tpot_vm" {
  for_each = var.tpot_vm_ids

  node_name     = var.node_name
  vm_id         = each.value
  enabled       = local.firewall_defaults.enabled
  input_policy  = "ACCEPT" # wide-net sensor; T-Pot manages its own per-service firewall
  output_policy = local.firewall_defaults.output_policy
  log_level_in  = "info"
  log_level_out = local.firewall_defaults.log_level_out

  depends_on = [proxmox_virtual_environment_cluster_firewall.main]
}

resource "proxmox_virtual_environment_firewall_rules" "tpot_vm" {
  for_each = var.tpot_vm_ids

  node_name = var.node_name
  vm_id     = each.value

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.outbound_internal.name
    comment        = "Outbound to internal only (apprise gateway + syslog 519)"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.outbound_https.name
    comment        = "Outbound HTTPS (T-Pot image/update + threat-intel pulls)"
  }

  depends_on = [proxmox_virtual_environment_firewall_options.tpot_vm]
}
