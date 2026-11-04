# Vikunja LXC firewall — native single-binary task-management app, web/API on
# vikunja_web (3456), state in the shared Postgres. Its security group and
# *_services_rules local live here, not in locals_rules.tf / security_groups.tf,
# to keep those files under the shared _file-size workflow's 12 KB gate — same
# split as nautobot_rules.tf / postgres_rules.tf.
#
# Live guest-layer rule: 3456 open from internal RFC1918, following the existing
# default-deny per-service allow model. The web UI is reached through Traefik
# (ingress.tf vikunja route); the tighter ingress-only source restriction is the
# network-layer (tofu-unifi) inter-VLAN rule, which ships staged-disabled — the
# guest firewall here is the live boundary. The binary is controller-staged (no
# package-manager egress) and its only dependencies are Postgres + DNS + apt, so
# egress is outbound-internal only — no outbound_https.

locals {
  vikunja_services_rules = [
    { proto = "tcp", dport = tostring(local.svc_ports.vikunja_web), source = local.internal_src, comment = "Vikunja web/API from internal" },
  ]
}

resource "proxmox_virtual_environment_cluster_firewall_security_group" "vikunja_services" {
  name    = "vikunja-svc"
  comment = "Vikunja web/API (${local.svc_ports.vikunja_web}) from internal networks — Traefik-fronted"

  dynamic "rule" {
    for_each = local.vikunja_services_rules
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

resource "proxmox_virtual_environment_firewall_options" "vikunja_container" {
  for_each = var.vikunja_container_ids

  node_name     = var.node_name
  container_id  = each.value
  enabled       = local.firewall_defaults.enabled
  input_policy  = local.firewall_defaults.input_policy
  output_policy = local.firewall_defaults.output_policy
  log_level_in  = local.firewall_defaults.log_level_in
  log_level_out = local.firewall_defaults.log_level_out

  # DHCP-first guest (deployment.json dhcp=true) behind DROP in/out. Without the
  # firewall's dhcp allow, its own DHCPDISCOVER/OFFER is dropped and it never
  # leases its reserved apps-VLAN IP. Same treatment as the s3 container.
  dhcp = true

  depends_on = [proxmox_virtual_environment_cluster_firewall.main]
}

resource "proxmox_virtual_environment_firewall_rules" "vikunja_container" {
  for_each = var.vikunja_container_ids

  node_name    = var.node_name
  container_id = each.value

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.internal_access.name
    comment        = "Internal access (SSH, ICMP)"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.vikunja_services.name
    comment        = "Vikunja web/API (TCP/${local.svc_ports.vikunja_web})"
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

  depends_on = [proxmox_virtual_environment_firewall_options.vikunja_container]
}
