# Security-group rule-list locals, split from locals.tf (12KB file-size gate).
# Security group rule definitions - use comma-joined source/dest for multi-network rules
# Proxmox natively supports comma-separated CIDRs in source/dest fields,
# so we generate one rule per protocol/port rather than one per network.
#
# DRY: every port literal here either references var.pipeline_constants
# (single source of truth from root locals.tf) or is a port not yet promoted
# to the constants map. Numeric ports are tostring()-converted because the
# proxmox provider's dport attribute expects string values.
locals {
  # Comma-separated internal networks for use in source/dest fields
  internal_src = join(",", var.internal_networks)

  # Local aliases to keep rule definitions readable
  svc_ports          = var.pipeline_constants.service_ports
  syslog_port_map    = var.pipeline_constants.syslog_port_map
  notification_ports = var.pipeline_constants.notification_ports
  vector_db_ports    = var.pipeline_constants.vector_db_ports
  netflow_ports      = var.pipeline_constants.netflow_ports
  honeypot_ports     = var.pipeline_constants.honeypot_ports
  ai_log_ports       = var.pipeline_constants.ai_log_ports

  # Syslog ports — derived from syslog_port_map so that adding a new source
  # family auto-expands the firewall surface. standard = app-facing HAProxy
  # frontends (514-518); high = backend ports HAProxy forwards to the Cribl
  # Edge listeners (1514-1518).
  #
  # Emitted as comma-separated lists rather than min:max ranges to avoid
  # accidentally over-permitting if a non-contiguous port (e.g. 9999) is
  # ever added to the map — see Gemini security review on #323.
  # Proxmox firewall dport accepts comma-separated port lists.
  syslog_standard_ports = [for k, v in local.syslog_port_map : v.standard]
  syslog_standard_range = join(",", [for v in sort(local.syslog_standard_ports) : tostring(v)])
  pipeline_syslog_ports = [for k, v in local.syslog_port_map : v.high]
  pipeline_syslog_range = join(",", [for v in sort(local.pipeline_syslog_ports) : tostring(v)])

  internal_access_rules = [
    { proto = "tcp", dport = "22", source = local.internal_src, comment = "SSH from internal networks" },
    { proto = "icmp", dport = null, source = local.internal_src, comment = "ICMP from internal networks" },
  ]

  splunk_services_rules = [
    { proto = "tcp", dport = tostring(local.svc_ports.splunk_web), source = local.internal_src, comment = "Splunk Web UI from internal" },
    { proto = "tcp", dport = tostring(local.svc_ports.splunk_hec), source = local.internal_src, comment = "Splunk HEC from internal" },
    { proto = "tcp", dport = tostring(local.svc_ports.splunk_forwarding), source = local.internal_src, comment = "Splunk Forwarding (TCP ${local.svc_ports.splunk_forwarding}) from internal" },
  ]

  syslog_rules = [
    { proto = "udp", dport = local.syslog_standard_range, source = local.internal_src, comment = "Standard syslog frontends UDP (${local.syslog_standard_range}) from internal" },
    { proto = "tcp", dport = local.syslog_standard_range, source = local.internal_src, comment = "Standard syslog frontends TCP (${local.syslog_standard_range}) from internal" },
    { proto = "udp", dport = local.pipeline_syslog_range, source = local.internal_src, comment = "Pipeline syslog backends UDP (${local.pipeline_syslog_range}) from internal" },
    { proto = "tcp", dport = local.pipeline_syslog_range, source = local.internal_src, comment = "Pipeline syslog backends TCP (${local.pipeline_syslog_range}) from internal" },
  ]

  pipeline_services_rules = [
    { proto = "tcp", dport = tostring(local.svc_ports.haproxy_stats), source = local.internal_src, comment = "HAProxy stats from internal" },
    { proto = "tcp", dport = tostring(local.svc_ports.cribl_edge_api), source = local.internal_src, comment = "Cribl Edge API from internal" },
    { proto = "tcp", dport = tostring(local.svc_ports.splunk_hec), source = local.internal_src, comment = "Cribl Edge HEC input (netmon Telegraf push, reuses the splunk_hec port) from internal" },
    { proto = "tcp", dport = tostring(local.svc_ports.cribl_s2s), source = local.internal_src, comment = "Cribl S2S frontend (remote Edge -> HAProxy -> Stream) from internal" },
    { proto = "tcp", dport = tostring(local.svc_ports.cribl_s2s_metrics), source = local.internal_src, comment = "Cribl S2S metrics frontend (remote Edge -> HAProxy -> Stream) from internal" },
    { proto = "tcp", dport = tostring(local.svc_ports.cribl_pve_metrics), source = local.internal_src, comment = "Cribl PVE metrics frontend (Proxmox -> HAProxy -> Stream) from internal" },
  ]

  netflow_rules = [
    { proto = "udp", dport = tostring(local.netflow_ports.unifi), source = local.internal_src, comment = "NetFlow/IPFIX UDP from internal" },
  ]

  ntp_server_rules = [
    { proto = "udp", dport = tostring(local.svc_ports.ntp), source = local.internal_src, comment = "NTP chrony server (UDP ${local.svc_ports.ntp}) from internal" },
  ]

  # node_exporter scrape on the Proxmox hosts, deliberately scoped to the siem
  # VLAN (the Cribl Edge scrapers) instead of internal_src — host metrics need
  # exactly one consumer. Missing CIDR -> "" -> rule is inert, same contract as
  # the zero-trust sources.
  node_exporter_rules = [
    { proto = "tcp", dport = tostring(local.svc_ports.node_exporter), source = local.zt_src["siem"], comment = "node_exporter scrape (TCP ${local.svc_ports.node_exporter}) from siem VLAN Cribl Edge" },
  ]

  notification_services_rules = [
    { proto = "tcp", dport = tostring(local.notification_ports.mailpit_smtp), source = local.internal_src, comment = "Mailpit SMTP from internal" },
    { proto = "tcp", dport = tostring(local.notification_ports.mailpit_web), source = local.internal_src, comment = "Mailpit Web UI from internal" },
    { proto = "tcp", dport = tostring(local.notification_ports.ntfy_http), source = local.internal_src, comment = "ntfy HTTP from internal" },
  ]

  vectordb_services_rules = [
    { proto = "tcp", dport = tostring(local.vector_db_ports.qdrant_http), source = local.internal_src, comment = "Qdrant HTTP API from internal" },
    { proto = "tcp", dport = tostring(local.vector_db_ports.qdrant_grpc), source = local.internal_src, comment = "Qdrant gRPC from internal" },
  ]

  # honeypot_services_rules + honeypot_notify_services_rules are defined in
  # honeypot_rules.tf (alongside the honeypot resources) to keep this file under
  # the shared _file-size workflow's 12 KB limit. locals merge across files in a
  # module, so the rule lists referenced by the security groups resolve the same.

  apt_cacher_ng_services_rules = [
    { proto = "tcp", dport = tostring(local.svc_ports.apt_cacher_ng), source = local.internal_src, comment = "apt-cacher-ng from internal" },
  ]

  cribl_stream_services_rules = [
    { proto = "tcp", dport = tostring(local.svc_ports.cribl_stream_api), source = local.internal_src, comment = "Cribl Stream API from internal" },
    { proto = "tcp", dport = tostring(local.svc_ports.cribl_s2s), source = local.internal_src, comment = "Cribl S2S input (HAProxy -> Stream) from internal" },
    { proto = "tcp", dport = tostring(local.svc_ports.cribl_s2s_metrics), source = local.internal_src, comment = "Cribl S2S metrics input (HAProxy -> Stream) from internal" },
    { proto = "tcp", dport = tostring(local.svc_ports.cribl_pve_metrics), source = local.internal_src, comment = "Cribl PVE metrics input (HAProxy -> Stream) from internal" },
    { proto = "tcp", dport = tostring(local.svc_ports.cribl_prometheus_rw), source = local.internal_src, comment = "Prometheus remote_write receiver from internal" },
  ]

  s3_services_rules = [
    { proto = "tcp", dport = tostring(local.svc_ports.object_storage_s3), source = local.internal_src, comment = "Object storage (RustFS) S3 API from internal" },
    { proto = "tcp", dport = tostring(local.svc_ports.object_storage_console), source = local.internal_src, comment = "Object storage (RustFS) Console from internal" },
  ]

  # OpenBao API/UI (8200) is reached via Traefik (internal RFC1918). The Raft
  # cluster port (8201) is peer-to-peer and remains internal-only.
  openbao_services_rules = [
    { proto = "tcp", dport = tostring(local.svc_ports.openbao_api), source = local.internal_src, comment = "OpenBao API/UI from internal" },
    { proto = "tcp", dport = tostring(local.svc_ports.openbao_cluster), source = local.internal_src, comment = "OpenBao Raft cluster from internal" },
  ]

  # Outbound to internal RFC1918 only (blocks internet egress)
  outbound_internal_rules = [
    { proto = "tcp", dest = local.internal_src, comment = "Outbound TCP to internal" },
    { proto = "udp", dest = local.internal_src, comment = "Outbound UDP to internal" },
    { proto = "icmp", dest = local.internal_src, comment = "Outbound ICMP to internal" },
  ]

  # Cribl Free licensing requires anonymized telemetry to cribl.io (CDN-
  # fronted — the IPs rotate, so no stable dest CIDR exists). When telemetry
  # is blocked past the grace period, the license disables ALL inputs:
  # observed 2026-06-10 on every cribl LXC — listeners stayed bound while
  # each incoming event was silently dropped, killing the whole pipeline.
  # Outbound TCP 443 to any destination is the minimal opening that keeps
  # inputs licensed; tarball downloads still come from the RustFS (s3) mirror, and
  # the group is attached only to cribl containers (not HAProxy).
  outbound_https_rules = [
    { proto = "tcp", dport = "443", dest = null, comment = "Outbound HTTPS — Cribl license telemetry (CDN-fronted, no stable dest CIDR)" },
  ]

  outbound_http_rules = [
    { proto = "tcp", dport = "80", dest = null, comment = "Outbound HTTP to anywhere" },
  ]

  # iDRAC KVM: inbound noVNC HTTP ports from internal; egress reuses outbound_internal
  idrac_kvm_services_rules = [
    { proto = "tcp", dport = tostring(local.svc_ports.idrac_kvm_r410), source = local.internal_src, comment = "iDRAC HTML5 KVM R410 (TCP ${local.svc_ports.idrac_kvm_r410}) from internal" },
    { proto = "tcp", dport = tostring(local.svc_ports.idrac_kvm_r710), source = local.internal_src, comment = "iDRAC HTML5 KVM R710 (TCP ${local.svc_ports.idrac_kvm_r710}) from internal" },
  ]

  # Monitoring: inbound network-quality stack ports from internal — SmokePing UI
  # plus the Prometheus exporters (speedtest, smokeping_prober, blackbox, atlas)
  # and the irtt UDP server. All scrape/probe-inbound; egress stays open (output
  # ACCEPT on the container) so fping/DNS/HTTPS/irtt probes can reach internal and
  # external targets — see monitoring_rules.tf. Ports are DRY from pipeline_constants.
  monitoring_services_rules = [
    { proto = "tcp", dport = tostring(local.svc_ports.smokeping_web), source = local.internal_src, comment = "SmokePing web UI (TCP ${local.svc_ports.smokeping_web}) from internal" },
    { proto = "tcp", dport = tostring(local.svc_ports.speedtest_exporter), source = local.internal_src, comment = "speedtest-exporter Prometheus metrics (TCP ${local.svc_ports.speedtest_exporter}) from internal" },
    { proto = "tcp", dport = tostring(local.svc_ports.smokeping_prober), source = local.internal_src, comment = "smokeping_prober Prometheus metrics (TCP ${local.svc_ports.smokeping_prober}) from internal" },
    { proto = "tcp", dport = tostring(local.svc_ports.blackbox_exporter), source = local.internal_src, comment = "blackbox_exporter Prometheus metrics (TCP ${local.svc_ports.blackbox_exporter}) from internal" },
    { proto = "tcp", dport = tostring(local.svc_ports.atlas_exporter), source = local.internal_src, comment = "atlas_exporter (RIPE Atlas) Prometheus metrics (TCP ${local.svc_ports.atlas_exporter}) from internal" },
    { proto = "udp", dport = tostring(local.svc_ports.irtt), source = local.internal_src, comment = "irtt isochronous RTT/jitter server (UDP ${local.svc_ports.irtt}) from internal" },
  ]
}
