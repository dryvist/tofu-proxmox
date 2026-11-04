# Glance LXC firewall — dashboard, web UI on glance_web (8080), single Go
# binary reading glance.yml from a persistent mount. Its security group and
# *_services_rules local live here, not in locals_rules.tf / security_groups.tf,
# to keep those under the shared _file-size workflow's 12 KB gate — same split
# as homarr_rules.tf, whose shape this follows deliberately.
#
# Live guest-layer rule: 8080 open from internal RFC1918, following the existing
# default-deny per-service allow model. The UI is reached through Traefik
# (ingress.tf glance route).
#
# The Authelia gate on that route is not optional here: Glance ships NO
# authentication of its own, so forwardAuth is the only thing in front of it.
#
# Egress: internal, plus HTTPS/HTTP — Glance's feed widgets fetch from external
# sources at page load, and its release is resolved at install time.
locals {
  glance_services_rules = [
    { proto = "tcp", dport = tostring(local.svc_ports.glance_web), source = local.internal_src, comment = "Glance dashboard from internal" },
  ]
}

resource "proxmox_virtual_environment_cluster_firewall_security_group" "glance_services" {
  name    = "glance-svc"
  comment = "Glance dashboard (${local.svc_ports.glance_web}) from internal networks — Traefik-fronted"

  dynamic "rule" {
    for_each = local.glance_services_rules
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

resource "proxmox_virtual_environment_firewall_options" "glance_container" {
  for_each = var.glance_container_ids

  node_name     = var.node_name
  container_id  = each.value
  enabled       = local.firewall_defaults.enabled
  input_policy  = local.firewall_defaults.input_policy
  output_policy = local.firewall_defaults.output_policy
  log_level_in  = local.firewall_defaults.log_level_in
  log_level_out = local.firewall_defaults.log_level_out

  # DHCP-first guest (deployment.json dhcp=true) behind DROP in/out. Without the
  # firewall's dhcp allow, its own DHCPDISCOVER/OFFER is dropped and it never
  # leases its apps-VLAN IP. Same treatment as the homarr container.
  dhcp = true

  depends_on = [proxmox_virtual_environment_cluster_firewall.main]
}

resource "proxmox_virtual_environment_firewall_rules" "glance_container" {
  for_each = var.glance_container_ids

  node_name    = var.node_name
  container_id = each.value

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.internal_access.name
    comment        = "Internal access (SSH, ICMP)"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.glance_services.name
    comment        = "Glance dashboard (TCP/${local.svc_ports.glance_web})"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.outbound_internal.name
    comment        = "Outbound to internal only"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.outbound_https.name
    comment        = "Outbound HTTPS (external feed sources, release download at install)"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.outbound_http.name
    comment        = "Outbound HTTP (apt via the internal proxy, OCSP/CRL during TLS handshake)"
  }

  depends_on = [proxmox_virtual_environment_firewall_options.glance_container]
}
