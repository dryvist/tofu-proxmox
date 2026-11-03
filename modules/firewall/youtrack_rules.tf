# YouTrack LXC firewall — web UI and API on youtrack_web (8080). Its security group and *_services_rules local live here,
# not in locals_rules.tf / security_groups.tf, to keep those files under the
# shared _file-size workflow's 12 KB gate — same split as vikunja_rules.tf.
#
# Guest-layer rule: 8080 open from internal RFC1918, following the existing
# default-deny per-service allow model. The web UI is reached through Traefik
# (ingress.tf youtrack route, sso = false). Egress mirrors vikunja_rules.tf:
# outbound internal, plus HTTPS and HTTP.

locals {
  youtrack_services_rules = [
    { proto = "tcp", dport = tostring(local.svc_ports.youtrack_web), source = local.internal_src, comment = "YouTrack web/API from internal" },
  ]
}

resource "proxmox_virtual_environment_cluster_firewall_security_group" "youtrack_services" {
  name    = "youtrack-svc"
  comment = "YouTrack web/API (${local.svc_ports.youtrack_web}) from internal networks — Traefik-fronted"

  dynamic "rule" {
    for_each = local.youtrack_services_rules
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

resource "proxmox_virtual_environment_firewall_options" "youtrack_container" {
  for_each = var.youtrack_container_ids

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

resource "proxmox_virtual_environment_firewall_rules" "youtrack_container" {
  for_each = var.youtrack_container_ids

  node_name    = lookup(var.container_nodes, tostring(each.value), var.node_name)
  container_id = each.value

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.internal_access.name
    comment        = "Internal access (SSH, ICMP)"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.youtrack_services.name
    comment        = "YouTrack web/API (TCP/${local.svc_ports.youtrack_web})"
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

  depends_on = [proxmox_virtual_environment_firewall_options.youtrack_container]
}
