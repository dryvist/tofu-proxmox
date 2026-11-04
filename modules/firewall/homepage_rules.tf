# Homepage (gethomepage) LXC firewall — service-launcher dashboard, web UI on
# homepage_web (3000), config rendered to YAML on a persistent mount. Its
# security group and *_services_rules local live here, not in locals_rules.tf /
# security_groups.tf, to keep those under the shared _file-size workflow's 12 KB
# gate — same split as homarr_rules.tf, whose shape this follows deliberately.
#
# Live guest-layer rule: 3000 open from internal RFC1918, following the existing
# default-deny per-service allow model. The UI is reached through Traefik
# (ingress.tf homepage route), Authelia-gated.
#
# Egress: internal, plus HTTPS/HTTP. HTTPS is load-bearing rather than
# incidental — Homepage does not bundle its icon sets, it fetches them from a
# remote CDN in the browser and resolves its own release at install time.
locals {
  homepage_services_rules = [
    { proto = "tcp", dport = tostring(local.svc_ports.homepage_web), source = local.internal_src, comment = "Homepage dashboard from internal" },
  ]
}

resource "proxmox_virtual_environment_cluster_firewall_security_group" "homepage_services" {
  name    = "homepage-svc"
  comment = "Homepage dashboard (${local.svc_ports.homepage_web}) from internal networks — Traefik-fronted"

  dynamic "rule" {
    for_each = local.homepage_services_rules
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

resource "proxmox_virtual_environment_firewall_options" "homepage_container" {
  for_each = var.homepage_container_ids

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

resource "proxmox_virtual_environment_firewall_rules" "homepage_container" {
  for_each = var.homepage_container_ids

  node_name    = var.node_name
  container_id = each.value

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.internal_access.name
    comment        = "Internal access (SSH, ICMP)"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.homepage_services.name
    comment        = "Homepage dashboard (TCP/${local.svc_ports.homepage_web})"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.outbound_internal.name
    comment        = "Outbound to internal only"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.outbound_https.name
    comment        = "Outbound HTTPS (icon-set CDN, release download at install)"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.outbound_http.name
    comment        = "Outbound HTTP (apt via the internal proxy, OCSP/CRL during TLS handshake)"
  }

  depends_on = [proxmox_virtual_environment_firewall_options.homepage_container]
}
