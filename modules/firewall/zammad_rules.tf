# Zammad LXC firewall — native ITSM/ticketing app (Rails + colocated
# Elasticsearch + Redis), web/API on zammad_web (8080) behind nginx, state in
# the shared Postgres. Its security group and *_services_rules local live here,
# not in locals_rules.tf / security_groups.tf, to keep those files under the
# shared _file-size workflow's 12 KB gate — same split as vikunja_rules.tf /
# nautobot_rules.tf / postgres_rules.tf.
#
# Live guest-layer rule: 8080 open from internal RFC1918, following the existing
# default-deny per-service allow model. The web UI is reached through Traefik
# (ingress.tf zammad route); the tighter ingress-only source restriction is the
# network-layer (tofu-unifi) inter-VLAN rule, which ships staged-disabled — the
# guest firewall here is the live boundary. Egress is outbound-internal only:
# Postgres + Redis(loopback) + DNS + Mailpit are all internal, and the Zammad
# and Elasticsearch apt repos are reached through the internal apt-cacher-ng
# proxy (which does the external passthrough) — so no outbound_https, same as
# postgres/vikunja.

locals {
  zammad_services_rules = [
    { proto = "tcp", dport = tostring(local.svc_ports.zammad_web), source = local.internal_src, comment = "Zammad web/API from internal" },
  ]
}

resource "proxmox_virtual_environment_cluster_firewall_security_group" "zammad_services" {
  name    = "zammad-svc"
  comment = "Zammad web/API (${local.svc_ports.zammad_web}) from internal networks — Traefik-fronted"

  dynamic "rule" {
    for_each = local.zammad_services_rules
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

resource "proxmox_virtual_environment_firewall_options" "zammad_container" {
  for_each = var.zammad_container_ids

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

resource "proxmox_virtual_environment_firewall_rules" "zammad_container" {
  for_each = var.zammad_container_ids

  node_name    = var.node_name
  container_id = each.value

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.internal_access.name
    comment        = "Internal access (SSH, ICMP)"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.zammad_services.name
    comment        = "Zammad web/API (TCP/${local.svc_ports.zammad_web})"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.outbound_internal.name
    comment        = "Outbound to internal services (DNS/LDAP/NTP/Postgres/Redis/Elasticsearch)"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.outbound_https.name
    comment        = "Outbound HTTPS (OIDC SSO discovery, updates, webhooks)"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.outbound_http.name
    comment        = "Outbound HTTP (OCSP/CRL checks during TLS handshake)"
  }

  depends_on = [proxmox_virtual_environment_firewall_options.zammad_container]
}
