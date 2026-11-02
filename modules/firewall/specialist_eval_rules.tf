# Specialist evaluation guests get only the web port for their platform tag.
# A platform whose port constant is absent is left out, and the check below
# then flags any guest carrying that platform tag.
locals {
  specialist_eval_service_ports = {
    "sim-eval"      = try(local.svc_ports.sim_web, null)
    "langflow-eval" = try(local.svc_ports.langflow_web, null)
    "dify-eval"     = try(local.svc_ports.dify_web, null)
  }

  specialist_eval_service_rules = { for tag, rule in {
    "sim-eval" = {
      name          = "spec-eval-sim"
      dport         = local.specialist_eval_service_ports["sim-eval"]
      group_comment = "Sim evaluation web UI from internal"
      guest_comment = "Sim evaluation service"
    }
    "langflow-eval" = {
      name          = "spec-eval-langflow"
      dport         = local.specialist_eval_service_ports["langflow-eval"]
      group_comment = "LangFlow evaluation web UI from internal"
      guest_comment = "LangFlow evaluation service"
    }
    "dify-eval" = {
      name          = "spec-eval-dify"
      dport         = local.specialist_eval_service_ports["dify-eval"]
      group_comment = "Dify evaluation web UI from internal"
      guest_comment = "Dify evaluation service"
    }
  } : tag => merge(rule, { dport = tostring(rule.dport) }) if rule.dport != null }
}

check "specialist_eval_platform_tag" {
  assert {
    condition = alltrue([
      for guest in values(var.specialist_eval_container_ids) :
      contains(keys(local.specialist_eval_service_rules), guest.platform_tag)
    ])
    error_message = "Each specialist-eval guest must have exactly one recognised platform tag."
  }
}

resource "proxmox_virtual_environment_cluster_firewall_security_group" "specialist_eval_services" {
  for_each = local.specialist_eval_service_rules

  name    = each.value.name
  comment = each.value.group_comment

  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = each.value.dport
    source  = local.internal_src
    comment = each.value.group_comment
  }
}

resource "proxmox_virtual_environment_firewall_options" "specialist_eval_container" {
  for_each = var.specialist_eval_container_ids

  node_name     = var.node_name
  container_id  = each.value.vm_id
  enabled       = local.firewall_defaults.enabled
  input_policy  = local.firewall_defaults.input_policy
  output_policy = local.firewall_defaults.output_policy
  log_level_in  = local.firewall_defaults.log_level_in
  log_level_out = local.firewall_defaults.log_level_out
  dhcp          = true

  depends_on = [proxmox_virtual_environment_cluster_firewall.main]
}

resource "proxmox_virtual_environment_firewall_rules" "specialist_eval_container" {
  for_each = var.specialist_eval_container_ids

  node_name    = var.node_name
  container_id = each.value.vm_id

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.internal_access.name
    comment        = "Internal access (SSH, ICMP)"
  }

  dynamic "rule" {
    for_each = contains(keys(local.specialist_eval_service_rules), each.value.platform_tag) ? [each.value.platform_tag] : []
    content {
      security_group = proxmox_virtual_environment_cluster_firewall_security_group.specialist_eval_services[rule.value].name
      comment        = local.specialist_eval_service_rules[rule.value].guest_comment
    }
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.outbound_internal.name
    comment        = "Outbound to internal (model endpoints, DNS)"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.outbound_https.name
    comment        = "Outbound HTTPS (external model APIs, package installs)"
  }

  depends_on = [
    proxmox_virtual_environment_firewall_options.specialist_eval_container,
    proxmox_virtual_environment_cluster_firewall_security_group.specialist_eval_services,
  ]
}
