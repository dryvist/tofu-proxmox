# =============================================================================
# Cluster-Level Security Groups: the AI tier
# =============================================================================
#
# Split out of security_groups.tf, which reached the shared 12 KB file-size
# gate. Terraform concatenates every .tf in a directory, so this is a file
# boundary and nothing else -- no module, no ordering, no addressing change.
# The same split already happened once for the llm_router/llm_fast groups,
# which live in llm_fabric_rules.tf for the same reason.

resource "proxmox_virtual_environment_cluster_firewall_security_group" "ai_orchestration_services" {
  name    = "ai-orch-svc" # Proxmox security-group names max 18 chars
  comment = "AI orchestration UIs (n8n 5678, LangFlow 7860, Dify 80, LangGraph 8124, Agent Chat UI 3000) from internal networks"

  dynamic "rule" {
    for_each = local.ai_orchestration_services_rules
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

resource "proxmox_virtual_environment_cluster_firewall_security_group" "langfuse_services" {
  name    = "langfuse-svc"
  comment = "Langfuse web UI + OTLP ingest (3000) from internal networks"

  dynamic "rule" {
    for_each = local.langfuse_services_rules
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

resource "proxmox_virtual_environment_cluster_firewall_security_group" "phoenix_services" {
  name    = "phoenix-svc"
  comment = "Phoenix web UI + OTLP ingest (6006/4317) + metrics (9090) from internal networks"

  dynamic "rule" {
    for_each = local.phoenix_services_rules
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

resource "proxmox_virtual_environment_cluster_firewall_security_group" "clickhouse_services" {
  name    = "clickhouse-svc"
  comment = "ClickHouse HTTP (8123) + native protocol (9000) from internal networks"

  dynamic "rule" {
    for_each = local.clickhouse_services_rules
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

# llm_router_services + llm_fast_services groups are in llm_fabric_rules.tf (size gate).

resource "proxmox_virtual_environment_cluster_firewall_security_group" "otel_ingest" {
  name    = "otel-ingest"
  comment = "Cribl Edge native OTLP sources (traces/metrics/logs, gRPC+HTTP) from the AI VLAN only"

  dynamic "rule" {
    for_each = local.otel_ingest_rules
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
