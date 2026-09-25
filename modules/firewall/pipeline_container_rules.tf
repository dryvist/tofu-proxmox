# Pipeline containers (HAProxy, Cribl Edge — syslog/NetFlow receivers).
#
# Extracted from container_rules.tf (alongside the zero-trust rule additions)
# to keep container_rules.tf under the shared _file-size workflow's 12 KB
# error threshold.

resource "proxmox_virtual_environment_firewall_options" "pipeline_container" {
  for_each = var.pipeline_container_ids

  node_name     = var.node_name
  container_id  = each.value
  enabled       = local.firewall_defaults.enabled
  input_policy  = local.firewall_defaults.input_policy
  output_policy = local.firewall_defaults.output_policy
  log_level_in  = local.firewall_defaults.log_level_in
  log_level_out = local.firewall_defaults.log_level_out

  depends_on = [proxmox_virtual_environment_cluster_firewall.main]
}

resource "proxmox_virtual_environment_firewall_rules" "pipeline_container" {
  for_each = var.pipeline_container_ids

  node_name    = var.node_name
  container_id = each.value

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.internal_access.name
    comment        = "Internal access (SSH, ICMP)"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.pipeline_services.name
    comment        = "Pipeline management (HAProxy stats, Cribl Edge API)"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.syslog.name
    comment        = "Syslog ingestion"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.netflow.name
    comment        = "NetFlow/IPFIX ingestion"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.ai_log_ingest.name
    comment        = "AI/LLM log-ingest TCP-JSON frontends (HAProxy -> Cribl Stream)"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.outbound_internal.name
    comment        = "Outbound to internal only"
  }

  # Cribl Edge only: license-telemetry HTTPS egress. HAProxy shares this
  # rule set but gets no internet egress.
  dynamic "rule" {
    for_each = contains(keys(var.cribl_edge_container_ids), each.key) ? [1] : []
    content {
      security_group = proxmox_virtual_environment_cluster_firewall_security_group.outbound_https.name
      comment        = "Outbound HTTPS (Cribl license telemetry)"
    }
  }

  # Cribl Edge only: native OTLP ingest (traces/metrics/logs) from the AI
  # orchestration apps on the ai VLAN. HAProxy in the same group gets no OTLP.
  dynamic "rule" {
    for_each = contains(keys(var.cribl_edge_container_ids), each.key) ? [1] : []
    content {
      security_group = proxmox_virtual_environment_cluster_firewall_security_group.otel_ingest.name
      comment        = "OTLP ingest (traces/metrics/logs) from the AI VLAN"
    }
  }

  # --- zero-trust (staged disabled) ---
  dynamic "rule" {
    for_each = local.zt_src
    content {
      enabled = local.zt_enabled
      type    = "in"
      action  = "ACCEPT"
      proto   = "udp"
      dport   = local.syslog_standard_range
      source  = rule.value
      comment = "ZT: syslog frontends from ${rule.key}"
    }
  }

  dynamic "rule" {
    for_each = local.zt_src
    content {
      enabled = local.zt_enabled
      type    = "in"
      action  = "ACCEPT"
      proto   = "udp"
      dport   = tostring(local.netflow_ports.unifi)
      source  = rule.value
      comment = "ZT: NetFlow from ${rule.key}"
    }
  }

  rule {
    enabled = local.zt_enabled
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = local.pipeline_syslog_range
    source  = join(",", compact([local.zt_src["pipeline"], local.zt_src["siem"]]))
    comment = "ZT: Cribl backend intra-pipeline"
  }

  rule {
    enabled = local.zt_enabled
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = tostring(local.svc_ports.cribl_s2s)
    source  = join(",", compact([local.zt_src["pipeline"], local.zt_src["siem"]]))
    comment = "ZT: Cribl S2S intra-pipeline"
  }

  rule {
    enabled = local.zt_enabled
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = tostring(local.svc_ports.cribl_s2s_metrics)
    source  = join(",", compact([local.zt_src["pipeline"], local.zt_src["siem"]]))
    comment = "ZT: Cribl S2S metrics intra-pipeline"
  }

  dynamic "rule" {
    for_each = contains(keys(var.cribl_edge_container_ids), each.key) ? [1] : []
    content {
      enabled = local.zt_enabled
      type    = "in"
      action  = "ACCEPT"
      proto   = "tcp"
      dport = join(",", [
        tostring(local.svc_ports.otel_traces_grpc), tostring(local.svc_ports.otel_traces_http),
        tostring(local.svc_ports.otel_metrics_grpc), tostring(local.svc_ports.otel_metrics_http),
        tostring(local.svc_ports.otel_logs_grpc), tostring(local.svc_ports.otel_logs_http),
      ])
      source  = local.zt_src["ai"]
      comment = "ZT: OTLP ingest from ai"
    }
  }

  rule {
    enabled = local.zt_enabled
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = tostring(local.svc_ports.cribl_prometheus_rw)
    source  = local.zt_src["siem"]
    comment = "ZT: Prometheus remote_write from siem"
  }

  depends_on = [proxmox_virtual_environment_firewall_options.pipeline_container]
}
