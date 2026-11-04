# Postgres LXC firewall — the shared native Postgres backing Nautobot (and later
# Vikunja/EspoCRM). Its security group and *_services_rules local live here, not
# in security_groups.tf / locals_rules.tf, to keep those files under the shared
# _file-size workflow's 12 KB gate — same split as honeypot_rules.tf.
#
# Live guest-layer rule: 5432 open from internal RFC1918, following the existing
# default-deny per-service allow model (openbao/s3/vectordb). The tighter
# apps-VLAN-only source restriction (Nautobot is today's only consumer) is the
# network-layer (tofu-unifi) inter-VLAN rule, which ships staged-disabled — the
# guest firewall here is the live boundary. A database never calls out, so egress
# is outbound-internal only (same as openbao/s3, no outbound_https).

locals {
  postgres_services_rules = [
    { proto = "tcp", dport = tostring(local.svc_ports.postgres_default), source = local.internal_src, comment = "Postgres (TCP ${local.svc_ports.postgres_default}) from internal" },
  ]
}

resource "proxmox_virtual_environment_cluster_firewall_security_group" "postgres_services" {
  name    = "postgres-svc"
  comment = "Postgres (${local.svc_ports.postgres_default}) from internal networks — shared DB for Nautobot/Vikunja/EspoCRM"

  dynamic "rule" {
    for_each = local.postgres_services_rules
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

resource "proxmox_virtual_environment_firewall_options" "postgres_container" {
  for_each = var.postgres_container_ids

  node_name     = var.node_name
  container_id  = each.value
  enabled       = local.firewall_defaults.enabled
  input_policy  = local.firewall_defaults.input_policy
  output_policy = local.firewall_defaults.output_policy
  log_level_in  = local.firewall_defaults.log_level_in
  log_level_out = local.firewall_defaults.log_level_out

  # DHCP-first guest (deployment.json dhcp=true) behind DROP in/out. Without the
  # firewall's dhcp allow, its own DHCPDISCOVER/OFFER is dropped and it never
  # leases its reserved data-VLAN IP. Same treatment as the s3 container.
  dhcp = true

  depends_on = [proxmox_virtual_environment_cluster_firewall.main]
}

resource "proxmox_virtual_environment_firewall_rules" "postgres_container" {
  for_each = var.postgres_container_ids

  node_name    = var.node_name
  container_id = each.value

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.internal_access.name
    comment        = "Internal access (SSH, ICMP)"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.postgres_services.name
    comment        = "Postgres (TCP/${local.svc_ports.postgres_default})"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.outbound_internal.name
    comment        = "Outbound to internal only"
  }

  depends_on = [proxmox_virtual_environment_firewall_options.postgres_container]
}
