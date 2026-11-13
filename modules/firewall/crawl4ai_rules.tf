# Crawl4AI API firewall. Keep its API port in a dedicated security group so
# the shared AI-orchestration group does not expose it to all internal sources.

locals {
  crawl4ai_services_rules = [
    { proto = "tcp", dport = tostring(local.svc_ports.crawl4ai_api), source = local.ai_src, comment = "Crawl4AI API from the AI VLAN ingress source only" },
  ]
}

resource "proxmox_virtual_environment_cluster_firewall_security_group" "crawl4ai_services" {
  name    = "crawl4ai-svc"
  comment = "Crawl4AI API (${local.svc_ports.crawl4ai_api}) from the AI VLAN ingress source only"

  dynamic "rule" {
    for_each = local.crawl4ai_services_rules
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

resource "proxmox_virtual_environment_firewall_options" "crawl4ai_container" {
  for_each = var.crawl4ai_container_ids

  node_name     = lookup(var.container_nodes, tostring(each.value), var.node_name)
  container_id  = each.value
  enabled       = local.firewall_defaults.enabled
  input_policy  = local.firewall_defaults.input_policy
  output_policy = local.firewall_defaults.output_policy
  log_level_in  = local.firewall_defaults.log_level_in
  log_level_out = local.firewall_defaults.log_level_out

  dhcp = true

  depends_on = [proxmox_virtual_environment_cluster_firewall.main]
}

resource "proxmox_virtual_environment_firewall_rules" "crawl4ai_container" {
  for_each = var.crawl4ai_container_ids

  node_name    = lookup(var.container_nodes, tostring(each.value), var.node_name)
  container_id = each.value

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.internal_access.name
    comment        = "Internal access (SSH, ICMP)"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.outbound_internal.name
    comment        = "Outbound to internal (DNS, NTP, syslog)"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.outbound_https.name
    comment        = "Outbound HTTPS (updates and external APIs)"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.outbound_http.name
    comment        = "Outbound HTTP (apt package mirrors, plain-HTTP crawl targets)"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.crawl4ai_services.name
    comment        = "Inbound API from the AI VLAN ingress source"
  }

  depends_on = [proxmox_virtual_environment_firewall_options.crawl4ai_container]
}
