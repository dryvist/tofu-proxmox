# Roster-agent firewalls. Each guest gets its own vm_id-keyed rules so DHCP
# addresses never need to appear in this policy.

locals {
  agent_owned_system_slugs = toset(flatten([
    for agent in values(var.agent_containers) : agent.owns
  ]))

  agent_owned_system_ports = {
    for slug, ports in var.agent_system_ports : slug => ports
    if contains(local.agent_owned_system_slugs, slug)
  }

  agent_owned_system_destinations = {
    for slug in keys(local.agent_owned_system_ports) : slug => join(",", try(var.agent_system_hosts[slug], []))
  }

  agent_owned_system_rules = flatten([
    for slug, ports in local.agent_owned_system_ports : [
      for port in ports : {
        slug = slug
        port = port
        dest = local.agent_owned_system_destinations[slug]
      }
    ]
  ])
}

resource "proxmox_virtual_environment_cluster_firewall_security_group" "agent_owned_system" {
  for_each = local.agent_owned_system_ports

  name    = "owned-${each.key}"
  comment = "Roster agent access to owned ${each.key} system hosts"

  dynamic "rule" {
    for_each = each.value
    content {
      type    = "out"
      action  = "ACCEPT"
      proto   = "tcp"
      dport   = tostring(rule.value)
      dest    = local.agent_owned_system_destinations[each.key]
      comment = "Owned ${each.key} service (TCP ${rule.value}) to system hosts"
    }
  }

  lifecycle {
    precondition {
      condition     = local.agent_owned_system_destinations[each.key] != ""
      error_message = "Owned system firewall rules require a configured system host destination."
    }
  }
}

resource "proxmox_virtual_environment_cluster_firewall_security_group" "agent_ingress_https" {
  for_each = length(var.agent_containers) > 0 ? { agents = var.agent_ingress_vip } : {}

  name    = "agent-ingress-https"
  comment = "Roster agents may reach HTTPS on the ingress VIP only"

  rule {
    type    = "out"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = "443"
    dest    = each.value
    comment = "HTTPS to the ingress VIP"
  }

  lifecycle {
    precondition {
      condition     = each.value != ""
      error_message = "Roster agents require a configured ingress VIP for HTTPS egress."
    }
  }
}

resource "proxmox_virtual_environment_firewall_options" "agent_container" {
  for_each = var.agent_containers

  node_name     = var.node_name
  container_id  = each.value.vm_id
  enabled       = local.firewall_defaults.enabled
  input_policy  = local.firewall_defaults.input_policy
  output_policy = local.firewall_defaults.output_policy
  log_level_in  = local.firewall_defaults.log_level_in
  log_level_out = local.firewall_defaults.log_level_out

  # Roster guests are DHCP-first and need DHCPDISCOVER/OFFER under DROP/DROP.
  dhcp = true

  depends_on = [proxmox_virtual_environment_cluster_firewall.main]
}

resource "proxmox_virtual_environment_firewall_rules" "agent_container" {
  for_each = var.agent_containers

  node_name    = var.node_name
  container_id = each.value.vm_id

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.internal_access.name
    comment        = "Internal access (SSH, ICMP)"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.ai_proxied_egress.name
    comment        = "Internal services, Squid proxy, and Cribl telemetry egress"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.agent_ingress_https["agents"].name
    comment        = "HTTPS to ingress VIP only"
  }

  dynamic "rule" {
    for_each = toset(each.value.owns)
    content {
      security_group = proxmox_virtual_environment_cluster_firewall_security_group.agent_owned_system[rule.value].name
      comment        = "Owned system access: ${rule.value}"
    }
  }

  lifecycle {
    precondition {
      condition     = length(setsubtract(toset(each.value.owns), toset(keys(var.agent_system_ports)))) == 0
      error_message = "Roster agent owns slugs must exist in the system port catalog."
    }

    precondition {
      condition     = var.agent_ingress_vip != ""
      error_message = "Roster agents require a configured ingress VIP for HTTPS egress."
    }

    # Every agent gets ai_proxied_egress, so a port in both sets would reach
    # the owned system from non-owner agents too.
    precondition {
      condition = length(setintersection(
        toset([for port in flatten(values(var.agent_system_ports)) : tostring(port)]),
        toset([for rule in local.ai_proxied_egress_rules : rule.dport]),
      )) == 0
      error_message = "An owned system port is also in the shared AI egress profile, so non-owner agents could reach it."
    }
  }

  depends_on = [proxmox_virtual_environment_firewall_options.agent_container]
}
