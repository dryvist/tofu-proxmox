# =============================================================================
# Network-quality monitoring container firewall configuration
# =============================================================================
# Extracted into its own file (like idrac_rules.tf) so container_rules.tf stays
# under the shared _file-size workflow's 12 KB error threshold.
# The smokeping host is a Docker-in-LXC on the mgmt VLAN (tag "monitoring"). It
# runs SmokePing (web UI on host port 80) and a speedtest-exporter (Prometheus
# metrics on host port 9798), exposed via the monitoring_services security group
# (see security_groups.tf + locals.tf).
#
# Egress is OPEN (output_policy = ACCEPT), unlike most service containers: fping,
# DNS and HTTPS probes must reach internal targets across VLANs AND external
# endpoints (1.1.1.1, public resolvers, https targets) to measure network
# quality. There is therefore no outbound_internal rule here.

resource "proxmox_virtual_environment_firewall_options" "monitoring_container" {
  for_each = var.monitoring_container_ids

  node_name     = var.node_name
  container_id  = each.value
  enabled       = local.firewall_defaults.enabled
  input_policy  = local.firewall_defaults.input_policy
  output_policy = "ACCEPT"
  log_level_in  = local.firewall_defaults.log_level_in
  log_level_out = local.firewall_defaults.log_level_out

  depends_on = [proxmox_virtual_environment_cluster_firewall.main]
}

resource "proxmox_virtual_environment_firewall_rules" "monitoring_container" {
  for_each = var.monitoring_container_ids

  node_name    = var.node_name
  container_id = each.value

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.internal_access.name
    comment        = "Internal access (SSH, ICMP)"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.monitoring_services.name
    comment        = "Monitoring services (SmokePing web 80, speedtest-exporter 9798)"
  }

  depends_on = [proxmox_virtual_environment_firewall_options.monitoring_container]
}
