# LLM classifier firewall resources (llm-gpu-classify guests on the ai VLAN).
# Split from llm_fabric_rules.tf to keep both files under the 12 KB size gate.

resource "proxmox_virtual_environment_cluster_firewall_security_group" "llm_classify_services" {
  name    = "llm-classify-svc"
  comment = "LLM classifier API (${local.svc_ports.llm_classify_api}) from internal networks"

  dynamic "rule" {
    for_each = local.llm_classify_services_rules
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

# llm-classify containers (Laya System One classifier)

resource "proxmox_virtual_environment_firewall_options" "llm_classify_container" {
  for_each = var.llm_classify_container_ids

  node_name     = var.node_name
  container_id  = each.value
  enabled       = local.firewall_defaults.enabled
  input_policy  = local.firewall_defaults.input_policy
  output_policy = local.firewall_defaults.output_policy
  log_level_in  = local.firewall_defaults.log_level_in
  log_level_out = local.firewall_defaults.log_level_out

  dhcp = true

  depends_on = [proxmox_virtual_environment_cluster_firewall.main]
}

resource "proxmox_virtual_environment_firewall_rules" "llm_classify_container" {
  for_each = var.llm_classify_container_ids

  node_name    = var.node_name
  container_id = each.value

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.internal_access.name
    comment        = "Internal access (SSH, ICMP)"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.llm_classify_services.name
    comment        = "LLM classifier API from internal"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.outbound_internal.name
    comment        = "Outbound to internal (DNS, service dependencies)"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.outbound_https.name
    comment        = "Outbound HTTPS (model downloads, package installs)"
  }

  dynamic "rule" {
    for_each = var.prometheus_scraper_trusted_src != "" && contains(keys(var.gpu_telemetry_container_ids), each.key) ? [1] : []
    content {
      security_group = proxmox_virtual_environment_cluster_firewall_security_group.gpu_telemetry[0].name
      comment        = "NVIDIA DCGM metrics from the Prometheus scraper"
    }
  }

  depends_on = [proxmox_virtual_environment_firewall_options.llm_classify_container]
}
