# =============================================================================
# hermes-ui container firewall configuration
# =============================================================================
# Extracted into its own file (like hermes_agent_rules.tf / llm_redis's block
# in llm_fabric_rules.tf) so container_rules.tf stays under the shared
# _file-size workflow's 12 KB error threshold.
#
# hermes-ui is a companion web UI guest for the Hermes agent, carrying its OWN
# tag (hermes-ui, not hermes-agent) so its egress profile can be tightened
# later without touching the agent's. Same egress profile as hermes-agent for
# now — one of its two apps may call model providers directly:
#   - internal_access  : SSH + ICMP in from internal RFC1918 (management).
#   - outbound_internal: reach internal services (DNS, NTP, Splunk logging).
#   - outbound_https   : TCP 443 to anywhere, for the app that calls model
#                        providers directly.
#   - hermes_ui_services: the two web apps (both default to 3000 upstream,
#                        mapped to distinct host ports), from internal only.

locals {
  hermes_ui_services_rules = [
    { proto = "tcp", dport = tostring(local.svc_ports.hermes_ui_workspace), source = local.internal_src, comment = "hermes-ui primary app (TCP ${local.svc_ports.hermes_ui_workspace}) from internal" },
    { proto = "tcp", dport = tostring(local.svc_ports.hermes_ui_mission_control), source = local.internal_src, comment = "mission-control app (TCP ${local.svc_ports.hermes_ui_mission_control}) from internal" },
  ]
}

resource "proxmox_virtual_environment_cluster_firewall_security_group" "hermes_ui_services" {
  name    = "hermes-ui-svc"
  comment = "hermes-ui web apps (${local.svc_ports.hermes_ui_workspace}, ${local.svc_ports.hermes_ui_mission_control}) from internal networks — Traefik-fronted"

  dynamic "rule" {
    for_each = local.hermes_ui_services_rules
    content {
      type    = "in"
      action  = "ACCEPT"
      proto   = rule.value.proto
      dport   = rule.value.dport
      source  = rule.value.source
      comment = rule.value.comment
    }
  }
}

resource "proxmox_virtual_environment_firewall_options" "hermes_ui_container" {
  for_each = var.hermes_ui_container_ids

  node_name     = var.node_name
  container_id  = each.value
  enabled       = local.firewall_defaults.enabled
  input_policy  = local.firewall_defaults.input_policy
  output_policy = local.firewall_defaults.output_policy
  log_level_in  = local.firewall_defaults.log_level_in
  log_level_out = local.firewall_defaults.log_level_out

  # DHCP-first guest (no static ip_config) — same as hermes-agent — needs its
  # own DHCPDISCOVER/OFFER allowed behind DROP in/out policies or it never leases.
  dhcp = true

  depends_on = [proxmox_virtual_environment_cluster_firewall.main]
}

resource "proxmox_virtual_environment_firewall_rules" "hermes_ui_container" {
  for_each = var.hermes_ui_container_ids

  node_name    = var.node_name
  container_id = each.value

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.internal_access.name
    comment        = "Internal access (SSH, ICMP)"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.outbound_internal.name
    comment        = "Outbound to internal only (DNS, NTP, Splunk logging)"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.outbound_https.name
    comment        = "Outbound HTTPS (TCP 443) for the app that calls model providers directly"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.hermes_ui_services.name
    comment        = "Inbound web apps (Traefik-fronted) from internal"
  }

  depends_on = [proxmox_virtual_environment_firewall_options.hermes_ui_container]
}
