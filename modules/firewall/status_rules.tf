# Status guest (Gatus + Uptime Kuma) LXC firewall — Docker-in-LXC compose
# stack hosting catalog synthetics and the keystone status page. Shape matches
# homepage_rules.tf / grafana_rules.tf.
#
# Live guest-layer rules: gatus_web + uptime_kuma_web from internal. UIs are
# reached through Traefik (ingress.tf gatus / uptime-kuma routes), Authelia-gated.
#
# Egress: internal + HTTPS/HTTP — Gatus must reach Authelia-gated public URLs
# (and guest probe targets) every 60s; image pulls need HTTPS.

locals {
  status_services_rules = [
    { proto = "tcp", dport = tostring(local.svc_ports.gatus_web), source = local.internal_src, comment = "Gatus synthetics UI from internal" },
    { proto = "tcp", dport = tostring(local.svc_ports.uptime_kuma_web), source = local.internal_src, comment = "Uptime Kuma status UI from internal" },
  ]
}

resource "proxmox_virtual_environment_cluster_firewall_security_group" "status_services" {
  name    = "status-svc"
  comment = "Status guest (Gatus ${local.svc_ports.gatus_web} + Uptime Kuma ${local.svc_ports.uptime_kuma_web}) from internal — Traefik-fronted"

  dynamic "rule" {
    for_each = local.status_services_rules
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

resource "proxmox_virtual_environment_firewall_options" "status_container" {
  for_each = var.status_container_ids

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

resource "proxmox_virtual_environment_firewall_rules" "status_container" {
  for_each = var.status_container_ids

  node_name    = var.node_name
  container_id = each.value

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.internal_access.name
    comment        = "Internal access (SSH, ICMP)"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.status_services.name
    comment        = "Status guest (TCP/${local.svc_ports.gatus_web}+${local.svc_ports.uptime_kuma_web})"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.outbound_internal.name
    comment        = "Outbound to internal only"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.outbound_https.name
    comment        = "Outbound HTTPS (Gatus probes + image pulls)"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.outbound_http.name
    comment        = "Outbound HTTP (apt via the internal proxy, OCSP/CRL during TLS handshake)"
  }

  depends_on = [proxmox_virtual_environment_firewall_options.status_container]
}
