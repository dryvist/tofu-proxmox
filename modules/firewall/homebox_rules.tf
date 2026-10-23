locals {
  homebox_services_rules = [
    { proto = "tcp", dport = tostring(local.svc_ports.homebox_web), source = local.internal_src, comment = "Homebox web service" },
  ]
}

resource "proxmox_virtual_environment_cluster_firewall_security_group" "homebox_services" {
  name    = "homebox-svc"
  comment = "Homebox web service (${local.svc_ports.homebox_web})"

  dynamic "rule" {
    for_each = local.homebox_services_rules
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

resource "proxmox_virtual_environment_firewall_options" "homebox_container" {
  for_each = var.homebox_container_ids

  node_name     = var.node_name
  container_id  = each.value
  enabled       = local.firewall_defaults.enabled
  input_policy  = local.firewall_defaults.input_policy
  output_policy = local.firewall_defaults.output_policy
  log_level_in  = local.firewall_defaults.log_level_in
  log_level_out = local.firewall_defaults.log_level_out
  dhcp          = true

  depends_on = [proxmox_virtual_environment_cluster_firewall.main]
}

resource "proxmox_virtual_environment_firewall_rules" "homebox_container" {
  for_each = var.homebox_container_ids

  node_name    = var.node_name
  container_id = each.value

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.internal_access.name
    comment        = "Internal access (SSH, ICMP)"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.homebox_services.name
    comment        = "Homebox web service (TCP/${local.svc_ports.homebox_web})"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.outbound_internal.name
    comment        = "Outbound to internal only"
  }

  depends_on = [proxmox_virtual_environment_firewall_options.homebox_container]
}
