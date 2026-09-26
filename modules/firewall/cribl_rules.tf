# Cribl pipeline rule-list locals, split out of locals_rules.tf to keep that
# file under the shared _file-size workflow's 12 KB limit. locals merge
# across files in a module, so the rule lists referenced by the security
# groups resolve the same as before.
locals {
  pipeline_services_rules = [
    { proto = "tcp", dport = tostring(local.svc_ports.haproxy_stats), source = local.internal_src, comment = "HAProxy stats from internal" },
    { proto = "tcp", dport = tostring(local.svc_ports.cribl_edge_api), source = local.internal_src, comment = "Cribl Edge API from internal" },
    { proto = "tcp", dport = tostring(local.svc_ports.splunk_hec), source = local.internal_src, comment = "Cribl Edge HEC input (netmon Telegraf push, reuses the splunk_hec port) from internal" },
    { proto = "tcp", dport = tostring(local.svc_ports.cribl_s2s), source = local.internal_src, comment = "Cribl S2S frontend (remote Edge -> HAProxy -> Stream) from internal" },
    { proto = "tcp", dport = tostring(local.svc_ports.cribl_s2s_metrics), source = local.internal_src, comment = "Cribl S2S metrics frontend (remote Edge -> HAProxy -> Stream) from internal" },
    { proto = "tcp", dport = tostring(local.svc_ports.cribl_pve_metrics), source = local.internal_src, comment = "Cribl PVE metrics frontend (Proxmox -> HAProxy -> Stream) from internal" },
  ]

  cribl_stream_services_rules = [
    { proto = "tcp", dport = tostring(local.svc_ports.cribl_stream_api), source = local.internal_src, comment = "Cribl Stream API from internal" },
    { proto = "tcp", dport = tostring(local.svc_ports.cribl_s2s), source = local.internal_src, comment = "Cribl S2S input (HAProxy -> Stream) from internal" },
    { proto = "tcp", dport = tostring(local.svc_ports.cribl_s2s_metrics), source = local.internal_src, comment = "Cribl S2S metrics input (HAProxy -> Stream) from internal" },
    { proto = "tcp", dport = tostring(local.svc_ports.cribl_pve_metrics), source = local.internal_src, comment = "Cribl PVE metrics input (HAProxy -> Stream) from internal" },
    { proto = "tcp", dport = tostring(local.svc_ports.cribl_prometheus_rw), source = local.internal_src, comment = "Prometheus remote_write receiver from internal" },
  ]
}
