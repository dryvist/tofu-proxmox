# Leantime LXC firewall — native PHP install, web on leantime_web (80). Its
# security group and *_services_rules local live here, not in locals_rules.tf /
# security_groups.tf, to keep those files under the shared _file-size workflow's
# 12 KB gate — same split as vikunja_rules.tf.
#
# Guest-layer rule: 80 open from internal RFC1918, following the existing
# default-deny per-service allow model. The web UI is reached through Traefik
# (ingress.tf leantime route, sso = false). Egress mirrors vikunja_rules.tf:
# outbound internal, plus HTTPS and HTTP.

locals {
  leantime_services_rules = [
    { proto = "tcp", dport = tostring(local.svc_ports.leantime_web), source = local.internal_src, comment = "Leantime web from internal" },
  ]
}

resource "proxmox_virtual_environment_cluster_firewall_security_group" "leantime_services" {
  name    = "leantime-svc"
  comment = "Leantime web (${local.svc_ports.leantime_web}) from internal networks — Traefik-fronted"

  dynamic "rule" {
    for_each = local.leantime_services_rules
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

resource "proxmox_virtual_environment_firewall_options" "leantime_container" {
  for_each = var.leantime_container_ids

  node_name     = lookup(var.container_nodes, tostring(each.value), var.node_name)
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

resource "proxmox_virtual_environment_firewall_rules" "leantime_container" {
  for_each = var.leantime_container_ids

  node_name    = lookup(var.container_nodes, tostring(each.value), var.node_name)
  container_id = each.value

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.internal_access.name
    comment        = "Internal access (SSH, ICMP)"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.leantime_services.name
    comment        = "Leantime web (TCP/${local.svc_ports.leantime_web})"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.outbound_internal.name
    comment        = "Outbound to internal only"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.outbound_https.name
    comment        = "Outbound HTTPS (OIDC SSO discovery and API calls)"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.outbound_http.name
    comment        = "Outbound HTTP (OCSP/CRL checks during TLS handshake)"
  }

  depends_on = [proxmox_virtual_environment_firewall_options.leantime_container]
}
