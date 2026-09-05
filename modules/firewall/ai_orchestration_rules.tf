# AI orchestration tier firewall resources. The orchestration UIs (n8n, Dify,
# LangFlow, LangGraph) and the agent-exec runtime live on the ai VLAN; Langfuse
# lives on the siem VLAN. All are DHCP-first guests behind DROP in/out policies, so each gets
# `dhcp = true` (same reason as s3_rules.tf). The Cribl Edge OTLP
# ingest rule (from the ai VLAN) is attached to the pipeline containers in
# container_rules.tf; this file owns the app-side guests.
#
# Rule data lives here (not in locals.tf) so that file stays under the shared
# _file-size 12 KB error threshold. local.svc_ports / local.internal_src are
# defined in locals.tf — cross-file local refs resolve within the module.
locals {
  # AI VLAN CIDR — least-privilege source for the Cribl Edge OTLP ingest path
  # (only AI-orchestration apps emit OpenTelemetry). Inter-VLAN policy is also
  # enforced at UniFi; this scopes the Proxmox guest firewall to match.
  ai_src = var.ai_network

  # AI orchestration UIs (n8n, Dify, LangFlow, LangGraph) — inbound from internal
  # so admins reach the builders; egress (model endpoints, external APIs) via
  # outbound internal/HTTPS groups on the container. LangGraph opens two ports: its
  # in-memory `langgraph dev` API and the self-hosted Agent Chat UI that fronts it.
  # Ports DRY from pipeline_constants.
  ai_orchestration_services_rules = [
    { proto = "tcp", dport = tostring(local.svc_ports.n8n_web), source = local.internal_src, comment = "n8n web UI (TCP ${local.svc_ports.n8n_web}) from internal" },
    { proto = "tcp", dport = tostring(local.svc_ports.langflow_web), source = local.internal_src, comment = "LangFlow web UI (TCP ${local.svc_ports.langflow_web}) from internal" },
    { proto = "tcp", dport = tostring(local.svc_ports.dify_web), source = local.internal_src, comment = "Dify web UI (TCP ${local.svc_ports.dify_web}) from internal" },
    { proto = "tcp", dport = tostring(local.svc_ports.langgraph_api), source = local.internal_src, comment = "LangGraph server API (TCP ${local.svc_ports.langgraph_api}) from internal" },
    { proto = "tcp", dport = tostring(local.svc_ports.agent_chat_ui_web), source = local.internal_src, comment = "LangGraph Agent Chat UI (TCP ${local.svc_ports.agent_chat_ui_web}) from internal" },
    { proto = "tcp", dport = tostring(local.svc_ports.docling_serve_api), source = local.internal_src, comment = "docling-serve convert API (TCP ${local.svc_ports.docling_serve_api}) from internal" },
  ]

  # Langfuse — web UI + OTLP-receive on the same port (path-based). Inbound from
  # internal covers both the admin UI and Cribl's trace push from the pipeline VLAN.
  langfuse_services_rules = [
    { proto = "tcp", dport = tostring(local.svc_ports.langfuse_web), source = local.internal_src, comment = "Langfuse web + OTLP ingest (TCP ${local.svc_ports.langfuse_web}) from internal" },
  ]

  # ClickHouse — HTTP query interface + native TCP protocol. Internal only,
  # never fronted by ingress (no Traefik route, no WAN source).
  clickhouse_services_rules = [
    { proto = "tcp", dport = tostring(local.svc_ports.clickhouse_http), source = local.internal_src, comment = "ClickHouse HTTP (TCP ${local.svc_ports.clickhouse_http}) from internal" },
    { proto = "tcp", dport = tostring(local.svc_ports.clickhouse_native), source = local.internal_src, comment = "ClickHouse native protocol (TCP ${local.svc_ports.clickhouse_native}) from internal" },
  ]

  # OTEL ingest on Cribl Edge — native OTLP sources, one port per signal type
  # (traces/metrics/logs, gRPC+HTTP). Scoped to the AI VLAN (ai_src): only the
  # AI-orchestration apps emit here. All ports are TCP. DRY from pipeline_constants.
  otel_ingest_rules = [
    { proto = "tcp", dport = join(",", [
      tostring(local.svc_ports.otel_traces_grpc), tostring(local.svc_ports.otel_traces_http),
      tostring(local.svc_ports.otel_metrics_grpc), tostring(local.svc_ports.otel_metrics_http),
      tostring(local.svc_ports.otel_logs_grpc), tostring(local.svc_ports.otel_logs_http),
    ]), source = local.ai_src, comment = "OTLP ingest (traces/metrics/logs gRPC+HTTP) from the AI VLAN" },
  ]
}

# AI orchestration containers (n8n, Dify, LangFlow, LangGraph, agent-exec)

resource "proxmox_virtual_environment_firewall_options" "ai_orchestration_container" {
  for_each = var.ai_orchestration_container_ids

  node_name     = var.node_name
  container_id  = each.value
  enabled       = local.firewall_defaults.enabled
  input_policy  = local.firewall_defaults.input_policy
  output_policy = local.firewall_defaults.output_policy
  log_level_in  = local.firewall_defaults.log_level_in
  log_level_out = local.firewall_defaults.log_level_out

  # DHCP-first guests behind DROP policies need their own DHCPDISCOVER/OFFER
  # allowed or they never lease their reserved ai-VLAN address.
  dhcp = true

  depends_on = [proxmox_virtual_environment_cluster_firewall.main]
}

resource "proxmox_virtual_environment_firewall_rules" "ai_orchestration_container" {
  for_each = var.ai_orchestration_container_ids

  node_name    = var.node_name
  container_id = each.value

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.internal_access.name
    comment        = "Internal access (SSH, ICMP)"
  }

  # agent-exec is an egress-only runtime (no web UI) — skip the UI security group
  # for it so the UI ports are not opened on a guest that never serves them.
  dynamic "rule" {
    for_each = each.key != "agent-exec" ? [1] : []
    content {
      security_group = proxmox_virtual_environment_cluster_firewall_security_group.ai_orchestration_services.name
      comment        = "AI orchestration UIs (n8n, Dify, LangFlow, LangGraph)"
    }
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.outbound_internal.name
    comment        = "Outbound to internal (model endpoints, Cribl OTLP, DNS)"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.outbound_https.name
    comment        = "Outbound HTTPS (external model APIs, package installs)"
  }

  depends_on = [proxmox_virtual_environment_firewall_options.ai_orchestration_container]
}

# Langfuse container (LLM observability — web + OTLP ingest on 3000)

resource "proxmox_virtual_environment_firewall_options" "langfuse_container" {
  for_each = var.langfuse_container_ids

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

resource "proxmox_virtual_environment_firewall_rules" "langfuse_container" {
  for_each = var.langfuse_container_ids

  node_name    = var.node_name
  container_id = each.value

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.internal_access.name
    comment        = "Internal access (SSH, ICMP)"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.langfuse_services.name
    comment        = "Langfuse web + OTLP ingest (3000)"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.outbound_internal.name
    comment        = "Outbound to internal (object store, DNS)"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.outbound_https.name
    comment        = "Outbound HTTPS (updates/telemetry)"
  }

  depends_on = [proxmox_virtual_environment_firewall_options.langfuse_container]
}

# ClickHouse container (OLAP store — HTTP 8123 + native 9000, internal only)

resource "proxmox_virtual_environment_firewall_options" "clickhouse_container" {
  for_each = var.clickhouse_container_ids

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

resource "proxmox_virtual_environment_firewall_rules" "clickhouse_container" {
  for_each = var.clickhouse_container_ids

  node_name    = var.node_name
  container_id = each.value

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.internal_access.name
    comment        = "Internal access (SSH, ICMP)"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.clickhouse_services.name
    comment        = "ClickHouse HTTP + native protocol (8123/9000)"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.outbound_internal.name
    comment        = "Outbound to internal (object store, DNS)"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.outbound_https.name
    comment        = "Outbound HTTPS (updates/telemetry)"
  }

  depends_on = [proxmox_virtual_environment_firewall_options.clickhouse_container]
}
