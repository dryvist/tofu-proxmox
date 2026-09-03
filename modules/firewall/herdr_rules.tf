# =============================================================================
# herdr container firewall configuration
# =============================================================================
# Extracted into its own file (like hermes_ui_rules.tf) so container_rules.tf
# stays under the shared _file-size workflow's 12 KB error threshold.
#
# Two profiles, because the three herdr guests do not need the same reach and a
# single tag would hand the bridge and the dashboard the runtime's egress:
#
#   herdr (runtime)  — internal_access, outbound_internal, outbound_https.
#                      Every agent pane calls model providers, package
#                      registries and git forges from here, so broad outbound
#                      443 is the point of the guest, not an oversight.
#
#   herdr clients    — internal_access, outbound_internal, outbound_https, plus
#   (slack, ui)        the relay port inbound for the UI. They reach the runtime
#                      over SSH, which internal_access already covers. Slack
#                      Socket Mode and the Cloudflare-free relay are both
#                      OUTBOUND WebSockets, so neither guest needs an inbound
#                      rule for its messaging path — the only inbound listener
#                      in the set is the dashboard, and Traefik fronts it.
#
# Both sets are DHCP-first guests, so `dhcp = true` is required behind the DROP
# policies or they never lease — the same note hermes_ui_rules.tf carries.

locals {
  herdr_client_services_rules = [
    { proto = "tcp", dport = tostring(local.svc_ports.herdr_relay_ws), source = local.internal_src, comment = "herdr-remote relay + dashboard (TCP ${local.svc_ports.herdr_relay_ws}) from internal" },
  ]
}

resource "proxmox_virtual_environment_cluster_firewall_security_group" "herdr_client_services" {
  name    = "herdr-client-svc"
  comment = "herdr-remote relay/dashboard (${local.svc_ports.herdr_relay_ws}) from internal networks — Traefik-fronted"

  dynamic "rule" {
    for_each = local.herdr_client_services_rules
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

# --- runtime -----------------------------------------------------------------

resource "proxmox_virtual_environment_firewall_options" "herdr_container" {
  for_each = var.herdr_container_ids

  node_name     = var.node_name
  container_id  = each.value
  enabled       = local.firewall_defaults.enabled
  input_policy  = local.firewall_defaults.input_policy
  output_policy = local.firewall_defaults.output_policy
  log_level_in  = local.firewall_defaults.log_level_in
  log_level_out = local.firewall_defaults.log_level_out

  dhcp = true

  depends_on = [proxmox_virtual_environment_cluster_firewall.main]
}

resource "proxmox_virtual_environment_firewall_rules" "herdr_container" {
  for_each = var.herdr_container_ids

  node_name    = var.node_name
  container_id = each.value

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.internal_access.name
    comment        = "Internal access (SSH, ICMP) — also how the bridge and dashboard reach this runtime"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.outbound_internal.name
    comment        = "Outbound to internal only (DNS, NTP, Splunk logging)"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.outbound_https.name
    comment        = "Outbound HTTPS (TCP 443) for the agent CLIs' model providers, registries and git forges"
  }

  depends_on = [proxmox_virtual_environment_firewall_options.herdr_container]
}

# --- clients (slack bridge, web/phone dashboard) ------------------------------

resource "proxmox_virtual_environment_firewall_options" "herdr_client_container" {
  for_each = var.herdr_client_container_ids

  node_name     = var.node_name
  container_id  = each.value
  enabled       = local.firewall_defaults.enabled
  input_policy  = local.firewall_defaults.input_policy
  output_policy = local.firewall_defaults.output_policy
  log_level_in  = local.firewall_defaults.log_level_in
  log_level_out = local.firewall_defaults.log_level_out

  dhcp = true

  depends_on = [proxmox_virtual_environment_cluster_firewall.main]
}

resource "proxmox_virtual_environment_firewall_rules" "herdr_client_container" {
  for_each = var.herdr_client_container_ids

  node_name    = var.node_name
  container_id = each.value

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.internal_access.name
    comment        = "Internal access (SSH, ICMP) — outbound SSH to the herdr runtime rides this"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.outbound_internal.name
    comment        = "Outbound to internal only (DNS, NTP, Splunk logging)"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.outbound_https.name
    comment        = "Outbound HTTPS (TCP 443) — Slack Socket Mode dials out from here"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.herdr_client_services.name
    comment        = "Inbound relay/dashboard (Traefik-fronted) from internal"
  }

  depends_on = [proxmox_virtual_environment_firewall_options.herdr_client_container]
}
