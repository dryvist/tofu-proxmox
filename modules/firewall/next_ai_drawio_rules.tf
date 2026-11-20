locals {
  next_ai_drawio_services_rules = concat(
    var.next_ai_drawio_ingress_src == "" ? [] : [
      {
        proto   = "tcp"
        dport   = tostring(local.svc_ports.next_ai_drawio_web)
        source  = var.next_ai_drawio_ingress_src
        comment = "Next AI Draw.io web (TCP ${local.svc_ports.next_ai_drawio_web}) from ingress"
      }
    ],
    var.next_ai_drawio_mcp_src == "" ? [] : [
      {
        proto   = "tcp"
        dport   = tostring(local.svc_ports.next_ai_drawio_mcp)
        source  = var.next_ai_drawio_mcp_src
        comment = "Next AI Draw.io MCP (TCP ${local.svc_ports.next_ai_drawio_mcp}) from LiteLLM routers"
      }
    ],
  )
}

resource "proxmox_virtual_environment_cluster_firewall_security_group" "next_ai_drawio_services" {
  name    = "drawio-svc"
  comment = "Next AI Draw.io web from ingress and MCP from LiteLLM routers"

  dynamic "rule" {
    for_each = local.next_ai_drawio_services_rules
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
