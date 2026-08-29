# Grafana + VictoriaMetrics LXC firewall — observability guest running the two
# services as one compose stack (grafana_stack role). Its security group and
# *_services_rules local live here, not in locals_rules.tf / security_groups.tf,
# to keep those under the shared _file-size workflow's 12 KB gate — same split
# as homepage_rules.tf, whose shape this follows deliberately.
#
# Live guest-layer rules, default-deny per-service allow model:
#   grafana_web (3000)     — Grafana UI, reached through Traefik (ingress.tf
#                            grafana route), Authelia-gated.
#   victoriametrics (8428) — Prometheus remote_write receiver + Grafana
#                            datasource; internal pipeline writers push here.
#
# Egress: internal, plus HTTPS/HTTP. HTTPS is load-bearing — the compose stack
# pulls its pinned container images from a public registry at converge time.
locals {
  grafana_services_rules = [
    { proto = "tcp", dport = tostring(local.svc_ports.grafana_web), source = local.internal_src, comment = "Grafana UI from internal" },
    { proto = "tcp", dport = tostring(local.svc_ports.victoriametrics), source = local.internal_src, comment = "VictoriaMetrics remote_write + datasource from internal" },
  ]
}

resource "proxmox_virtual_environment_cluster_firewall_security_group" "grafana_services" {
  name    = "grafana-svc"
  comment = "Grafana UI (${local.svc_ports.grafana_web}) + VictoriaMetrics (${local.svc_ports.victoriametrics}) from internal networks — Traefik-fronted UI"

  dynamic "rule" {
    for_each = local.grafana_services_rules
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

resource "proxmox_virtual_environment_firewall_options" "grafana_container" {
  for_each = var.grafana_container_ids

  node_name     = var.node_name
  container_id  = each.value
  enabled       = local.firewall_defaults.enabled
  input_policy  = local.firewall_defaults.input_policy
  output_policy = local.firewall_defaults.output_policy
  log_level_in  = local.firewall_defaults.log_level_in
  log_level_out = local.firewall_defaults.log_level_out

  # DHCP-first guest (deployment.json dhcp=true) behind DROP in/out. Without
  # the firewall's dhcp allow, its own DHCPDISCOVER/OFFER is dropped and it
  # never leases an IP. Same treatment as the homepage container.
  dhcp = true

  depends_on = [proxmox_virtual_environment_cluster_firewall.main]
}

resource "proxmox_virtual_environment_firewall_rules" "grafana_container" {
  for_each = var.grafana_container_ids

  node_name    = var.node_name
  container_id = each.value

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.internal_access.name
    comment        = "Internal access (SSH, ICMP)"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.grafana_services.name
    comment        = "Grafana UI + VictoriaMetrics (TCP/${local.svc_ports.grafana_web}, TCP/${local.svc_ports.victoriametrics})"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.outbound_internal.name
    comment        = "Outbound to internal only"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.outbound_https.name
    comment        = "Outbound HTTPS (container-image pulls at converge)"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.outbound_http.name
    comment        = "Outbound HTTP (apt via the internal proxy, OCSP/CRL during TLS handshake)"
  }

  depends_on = [proxmox_virtual_environment_firewall_options.grafana_container]
}
