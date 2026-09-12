# MCP gateway LXC firewall — single-binary Python app (IBM mcp-context-forge)
# fronting every MCP client on mcp_gateway_web (4444). Its own *_services_rules
# local and security group live here, not in locals_rules.tf /
# security_groups.tf, to keep those files under the shared _file-size
# workflow's 12 KB gate — same split as vikunja_rules.tf.
#
# Live guest-layer rule: 4444 open from internal RFC1918, following the
# existing default-deny per-service allow model. The web/API is reached
# through Traefik (ingress.tf mcp-gateway route). Egress needs outbound_https
# for pip install at converge time and for any upstream MCP server it proxies
# to that requires an API key (Hugging Face, Postman, etc).

locals {
  mcp_gateway_services_rules = [
    { proto = "tcp", dport = tostring(local.svc_ports.mcp_gateway_web), source = local.internal_src, comment = "MCP gateway web/API from internal" },
  ]
}

resource "proxmox_virtual_environment_cluster_firewall_security_group" "mcp_gateway_services" {
  name    = "mcp-gateway-svc"
  comment = "MCP gateway web/API (${local.svc_ports.mcp_gateway_web}) from internal networks — Traefik-fronted"

  dynamic "rule" {
    for_each = local.mcp_gateway_services_rules
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

resource "proxmox_virtual_environment_firewall_options" "mcp_gateway_container" {
  for_each = var.mcp_gateway_container_ids

  node_name     = var.node_name
  container_id  = each.value
  enabled       = local.firewall_defaults.enabled
  input_policy  = local.firewall_defaults.input_policy
  output_policy = local.firewall_defaults.output_policy
  log_level_in  = local.firewall_defaults.log_level_in
  log_level_out = local.firewall_defaults.log_level_out

  # DHCP-first guest (deployment.json dhcp=true) behind DROP in/out. Without the
  # firewall's dhcp allow, its own DHCPDISCOVER/OFFER is dropped and it never
  # leases its reserved apps-VLAN IP. Same treatment as the vikunja container.
  dhcp = true

  depends_on = [proxmox_virtual_environment_cluster_firewall.main]
}

resource "proxmox_virtual_environment_firewall_rules" "mcp_gateway_container" {
  for_each = var.mcp_gateway_container_ids

  node_name    = var.node_name
  container_id = each.value

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.internal_access.name
    comment        = "Internal access (SSH, ICMP)"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.mcp_gateway_services.name
    comment        = "MCP gateway web/API (TCP/${local.svc_ports.mcp_gateway_web})"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.outbound_internal.name
    comment        = "Outbound to internal only"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.outbound_https.name
    comment        = "Outbound HTTPS (pip install, upstream MCP server API calls)"
  }

  depends_on = [proxmox_virtual_environment_firewall_options.mcp_gateway_container]
}
