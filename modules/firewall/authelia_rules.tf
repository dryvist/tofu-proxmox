# Authelia LXC firewall — native single-binary SSO portal / forwardAuth
# provider, portal + authz API on authelia_portal (9091). Its security group
# and *_services_rules local live here, not in locals_rules.tf /
# security_groups.tf, to keep those files under the shared _file-size
# workflow's 12 KB gate — same split as vikunja_rules.tf.
#
# Live guest-layer rule: 9091 open from internal RFC1918 — Traefik dials it for
# every forwardAuth subrequest and browsers reach the portal through Traefik
# (ingress.tf authelia route). State is local SQLite, notifications go to the
# internal SMTP relay, and the binary is controller-staged (no package-manager
# egress), so egress is outbound-internal only.

locals {
  authelia_services_rules = [
    { proto = "tcp", dport = tostring(local.svc_ports.authelia_portal), source = local.internal_src, comment = "Authelia portal + forwardAuth API from internal" },
  ]
}

resource "proxmox_virtual_environment_cluster_firewall_security_group" "authelia_services" {
  name    = "authelia-svc"
  comment = "Authelia portal/authz (${local.svc_ports.authelia_portal}) from internal networks — Traefik-fronted"

  dynamic "rule" {
    for_each = local.authelia_services_rules
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

resource "proxmox_virtual_environment_firewall_options" "authelia_container" {
  for_each = var.authelia_container_ids

  node_name     = var.node_name
  container_id  = each.value
  enabled       = local.firewall_defaults.enabled
  input_policy  = local.firewall_defaults.input_policy
  output_policy = local.firewall_defaults.output_policy
  log_level_in  = local.firewall_defaults.log_level_in
  log_level_out = local.firewall_defaults.log_level_out

  # Static mgmt-VLAN core guest (vmid-derived IP, like traefik/technitium) —
  # no dhcp allow needed.
  depends_on = [proxmox_virtual_environment_cluster_firewall.main]
}

resource "proxmox_virtual_environment_firewall_rules" "authelia_container" {
  for_each = var.authelia_container_ids

  node_name    = var.node_name
  container_id = each.value

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.internal_access.name
    comment        = "Internal access (SSH, ICMP)"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.authelia_services.name
    comment        = "Authelia portal/authz (TCP/${local.svc_ports.authelia_portal})"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.outbound_internal.name
    comment        = "Outbound to internal only"
  }

  depends_on = [proxmox_virtual_environment_firewall_options.authelia_container]
}
