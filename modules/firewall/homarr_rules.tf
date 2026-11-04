# Homarr LXC firewall — dashboard, web UI on homarr_web (7575), sqlite on its
# own rootfs, redis colocated and bound to loopback by the installer. Its
# security group and *_services_rules local live here, not in locals_rules.tf /
# security_groups.tf, to keep those under the shared _file-size workflow's 12 KB
# gate — same split as vikunja_rules.tf / zammad_rules.tf.
#
# Live guest-layer rule: 7575 open from internal RFC1918, following the existing
# default-deny per-service allow model. The UI is reached through Traefik
# (ingress.tf homarr route).
#
# Egress differs from vikunja on purpose. Vikunja's binary is controller-staged,
# so it needs no package-manager egress. Homarr is installed by a borrowed
# community-scripts installer that resolves its release from the GitHub API and
# pulls it from the release CDN at converge time, and runs an apt transaction
# first — so outbound HTTPS and HTTP are load-bearing here, not incidental.
# That extra egress surface is a real cost of borrowing the install step, and is
# recorded as such in the private docs ADR.

locals {
  homarr_services_rules = [
    { proto = "tcp", dport = tostring(local.svc_ports.homarr_web), source = local.internal_src, comment = "Homarr dashboard from internal" },
  ]
}

resource "proxmox_virtual_environment_cluster_firewall_security_group" "homarr_services" {
  name    = "homarr-svc"
  comment = "Homarr dashboard (${local.svc_ports.homarr_web}) from internal networks — Traefik-fronted"

  dynamic "rule" {
    for_each = local.homarr_services_rules
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

resource "proxmox_virtual_environment_firewall_options" "homarr_container" {
  for_each = var.homarr_container_ids

  node_name     = var.node_name
  container_id  = each.value
  enabled       = local.firewall_defaults.enabled
  input_policy  = local.firewall_defaults.input_policy
  output_policy = local.firewall_defaults.output_policy
  log_level_in  = local.firewall_defaults.log_level_in
  log_level_out = local.firewall_defaults.log_level_out

  # DHCP-first guest (deployment.json dhcp=true) behind DROP in/out. Without the
  # firewall's dhcp allow, its own DHCPDISCOVER/OFFER is dropped and it never
  # leases its apps-VLAN IP. Same treatment as the vikunja container.
  dhcp = true

  depends_on = [proxmox_virtual_environment_cluster_firewall.main]
}

resource "proxmox_virtual_environment_firewall_rules" "homarr_container" {
  for_each = var.homarr_container_ids

  node_name    = var.node_name
  container_id = each.value

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.internal_access.name
    comment        = "Internal access (SSH, ICMP)"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.homarr_services.name
    comment        = "Homarr dashboard (TCP/${local.svc_ports.homarr_web})"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.outbound_internal.name
    comment        = "Outbound to internal only"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.outbound_https.name
    comment        = "Outbound HTTPS (GitHub API + release CDN during the borrowed install)"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.outbound_http.name
    comment        = "Outbound HTTP (apt via the internal proxy, OCSP/CRL during TLS handshake)"
  }

  depends_on = [proxmox_virtual_environment_firewall_options.homarr_container]
}
