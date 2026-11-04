# Nautobot LXC firewall — native IPAM/DCIM source of truth (web UI on
# nautobot_web / 8080, Redis colocated). Its security group and *_services_rules
# local live here, not in security_groups.tf / locals_rules.tf, to keep those
# files under the shared _file-size workflow's 12 KB gate — same split as
# honeypot_rules.tf.
#
# Live guest-layer rule: 8080 open from internal RFC1918, following the existing
# default-deny per-service allow model. The web UI is reached through Traefik
# (ingress.tf nautobot route); the tighter ingress-only source restriction is the
# network-layer (tofu-unifi) inter-VLAN rule, which ships staged-disabled — the
# guest firewall here is the live boundary. Egress is outbound-internal (device
# onboarding + SSoT target internal Proxmox/iDRAC/UniFi) plus outbound-HTTPS for
# PyPI during converge (native install of nautobot + ssot + device-onboarding
# apps), same egress shape as the ai-orchestration Python apps.

locals {
  nautobot_services_rules = [
    { proto = "tcp", dport = tostring(local.svc_ports.nautobot_web), source = local.internal_src, comment = "Nautobot web UI (TCP ${local.svc_ports.nautobot_web}) from internal" },
  ]
}

resource "proxmox_virtual_environment_cluster_firewall_security_group" "nautobot_services" {
  name    = "nautobot-svc"
  comment = "Nautobot web UI (${local.svc_ports.nautobot_web}) from internal networks — IPAM/DCIM, Traefik-fronted"

  dynamic "rule" {
    for_each = local.nautobot_services_rules
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

resource "proxmox_virtual_environment_firewall_options" "nautobot_container" {
  for_each = var.nautobot_container_ids

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

resource "proxmox_virtual_environment_firewall_rules" "nautobot_container" {
  for_each = var.nautobot_container_ids

  node_name    = var.node_name
  container_id = each.value

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.internal_access.name
    comment        = "Internal access (SSH, ICMP)"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.nautobot_services.name
    comment        = "Nautobot web UI (TCP/${local.svc_ports.nautobot_web})"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.outbound_internal.name
    comment        = "Outbound to internal only"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.outbound_https.name
    comment        = "Outbound HTTPS (PyPI package installs during converge)"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.outbound_http.name
    comment        = "Outbound HTTP (OCSP/CRL checks during TLS handshake)"
  }

  depends_on = [proxmox_virtual_environment_firewall_options.nautobot_container]
}
