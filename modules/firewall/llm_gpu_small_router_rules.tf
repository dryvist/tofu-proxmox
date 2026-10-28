# LLM GPU small-router API firewall rule.
# Kept separate from llm-fast so port 10440 is attached only to tagged guests.
locals {
  llm_gpu_serving_container_ids = merge(var.llm_fast_container_ids, var.llm_gpu_small_router_container_ids)

  llm_gpu_small_router_services_rules = [
    {
      proto   = "tcp"
      dport   = tostring(local.svc_ports.llm_gpu_serving_api)
      source  = local.internal_src
      comment = "LLM GPU small-router API (TCP ${local.svc_ports.llm_gpu_serving_api}) from internal"
    },
  ]
}

resource "proxmox_virtual_environment_cluster_firewall_security_group" "llm_gpu_small_router_services" {
  name    = "llm-gpu-router-svc" # Proxmox security-group names max 18 chars
  comment = "LLM GPU small-router API (${local.svc_ports.llm_gpu_serving_api}) from internal networks"

  dynamic "rule" {
    for_each = local.llm_gpu_small_router_services_rules
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
