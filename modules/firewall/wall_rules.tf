# Wall LXC firewall — server-room wall display: static pages plus a read-only
# data gateway (native nginx) on wall_web. Same split and shape as
# glance_rules.tf.
#
# Live guest-layer rule: wall_web open from internal RFC1918, following the
# default-deny per-service allow model. The pages are reached through Traefik
# (ingress.tf wall route) behind Authelia; kiosk clients get a per-address
# bypass in the Authelia role.
#
# Egress: internal, so the gateway can reach its data sources, plus HTTPS/HTTP
# for the pinned release download and apt.
locals {
  wall_services_rules = [
    { proto = "tcp", dport = tostring(local.svc_ports.wall_web), source = local.internal_src, comment = "Wall pages and data gateway from internal" },
  ]
}

resource "proxmox_virtual_environment_cluster_firewall_security_group" "wall_services" {
  name    = "wall-svc"
  comment = "Wall (${local.svc_ports.wall_web}) from internal networks — Traefik-fronted"

  dynamic "rule" {
    for_each = local.wall_services_rules
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

resource "proxmox_virtual_environment_firewall_options" "wall_container" {
  for_each = var.wall_container_ids

  node_name     = var.node_name
  container_id  = each.value
  enabled       = local.firewall_defaults.enabled
  input_policy  = local.firewall_defaults.input_policy
  output_policy = local.firewall_defaults.output_policy
  log_level_in  = local.firewall_defaults.log_level_in
  log_level_out = local.firewall_defaults.log_level_out

  # DHCP-first guest (deployment.json dhcp=true) behind DROP in/out. Without the
  # firewall's dhcp allow, its own DHCPDISCOVER/OFFER is dropped and it never
  # leases its apps-VLAN IP. Same treatment as the glance container.
  dhcp = true

  depends_on = [proxmox_virtual_environment_cluster_firewall.main]
}

resource "proxmox_virtual_environment_firewall_rules" "wall_container" {
  for_each = var.wall_container_ids

  node_name    = var.node_name
  container_id = each.value

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.internal_access.name
    comment        = "Internal access (SSH, ICMP)"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.wall_services.name
    comment        = "Wall (TCP/${local.svc_ports.wall_web})"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.outbound_internal.name
    comment        = "Outbound to internal (data sources behind the gateway)"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.outbound_https.name
    comment        = "Outbound HTTPS (pinned release download at converge)"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.outbound_http.name
    comment        = "Outbound HTTP (apt via the internal proxy, OCSP/CRL during TLS handshake)"
  }

  depends_on = [proxmox_virtual_environment_firewall_options.wall_container]
}
