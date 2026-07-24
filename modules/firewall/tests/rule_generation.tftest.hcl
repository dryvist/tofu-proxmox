# Tests for firewall module rule generation
#
# Verifies the DRY source-joining approach: one rule per protocol/port combo,
# using comma-joined CIDRs as source, instead of one rule per network.
# Rule count must be independent of internal_networks list length.

mock_provider "proxmox" {}

variables {
  node_name          = "proxmox-1"
  management_network = "192.168.10.0/24"
  splunk_network     = "192.168.20.200"
  internal_networks  = ["192.168.0.0/16"]
  ai_network         = "192.168.50.0/24"
  pipeline_constants = {
    service_ports = {
      haproxy_stats     = 8404
      splunk_web        = 8000
      splunk_hec        = 8088
      splunk_mgmt       = 8089
      splunk_forwarding = 9997
      cribl_edge_api    = 9420
      cribl_stream_api  = 9000
      # Cribl S2S + Prometheus remote_write (referenced by pipeline/cribl_stream rules)
      cribl_s2s           = 10300
      cribl_prometheus_rw = 9201
      apt_cacher_ng       = 3142
      # Object storage (RustFS) — referenced by s3_services_rules
      object_storage_s3      = 9000
      object_storage_console = 9001
      openbao_api            = 8200
      openbao_cluster        = 8201
      postgres_default       = 5432
      redis_default          = 6379
      nautobot_web           = 8080
      vikunja_web            = 3456
      authelia_portal        = 9091
      zammad_web             = 8080
      ntp                    = 123
      idrac_kvm_r410         = 5410
      idrac_kvm_r710         = 5710
      # monitoring ports (own alignment group — longest key in the map)
      smokeping_web      = 80
      speedtest_exporter = 9798
      smokeping_prober   = 9374
      blackbox_exporter  = 9115
      atlas_exporter     = 9400
      irtt               = 2112
      node_exporter      = 9100
      # LLM fabric + agentgateway (referenced by llm_fabric/agentgateway rules)
      llm_fast_api         = 10434
      llm_router_api       = 4000
      agentgateway_proxy   = 8080
      agentgateway_admin   = 15000
      agentgateway_metrics = 15020
      # Hermes inbound webhook receiver + job API (referenced by hermes_webhook_services_rules)
      hermes_webhook   = 8644
      hermes_api       = 8642
      hermes_dashboard = 8080
      # AI orchestration + observability (referenced by ai_orchestration rules)
      n8n_web           = 5678
      dify_web          = 80
      langflow_web      = 7860
      langfuse_web      = 3000
      langgraph_api     = 8124
      agent_chat_ui_web = 3000
      otel_traces_grpc  = 4317
      otel_traces_http  = 4318
      otel_metrics_grpc = 4327
      otel_metrics_http = 4328
      otel_logs_grpc    = 4337
      otel_logs_http    = 4338
    }
    syslog_ports = {
      default   = 514
      unifi     = 1514
      palo_alto = 1515
      cisco_asa = 1516
      linux     = 1517
      windows   = 1518
    }
    syslog_port_map = {
      unifi     = { standard = 514, high = 1514, index = "unifi", sourcetype = "ubiquiti:unifi" }
      palo_alto = { standard = 515, high = 1515, index = "firewall", sourcetype = "pan:firewall" }
      cisco_asa = { standard = 516, high = 1516, index = "firewall", sourcetype = "cisco:asa" }
      linux     = { standard = 517, high = 1517, index = "os", sourcetype = "syslog" }
      windows   = { standard = 518, high = 1518, index = "os", sourcetype = "syslog" }
    }
    netflow_ports = {
      unifi = 2055
    }
    notification_ports = {
      mailpit_smtp = 1025
      mailpit_web  = 8025
      ntfy_http    = 8080
    }
    vector_db_ports = {
      qdrant_http = 6333
      qdrant_grpc = 6334
    }
    memory_ports = {
      hindsight_api = 8888
      hindsight_cp  = 9999
    }
    ai_log_ports = {
      claude_code    = 10311
      codex_cli      = 10312
      agy_cli        = 10313
      copilot_cli    = 10314
      vscode         = 10315
      macstudio_llm  = 10321
      macstudio_gate = 10322
      homelab_llm    = 10323
      openbao_audit  = 10331
    }
    # Media stack web UIs (referenced by media_rules.tf per-guest inbound rules)
    media_ports = {
      qbittorrent_web = 8080
      prowlarr_web    = 9696
      sonarr_web      = 8989
      radarr_web      = 7878
      plex_web        = 32400
      seerr_web       = 5055
      sortarr_web     = 8787
    }
    honeypot_ports = {
      apprise_api = 8000
      ftp         = 21
      telnet      = 23
      http        = 80
      https       = 443
      smb         = 445
      tftp        = 69
      snmp        = 161
      ntp         = 123
      sip         = 5060
      mssql       = 1433
      mysql       = 3306
      postgres    = 5432
      rdp         = 3389
      vnc         = 5900
      redis       = 6379
      git         = 9418
      http_proxy  = 8080
    }
    # IaC platform ports (referenced by ai_terrakube_rules.tf egress rules)
    iac_platform_ports = {
      terrakube_ui       = 28080
      terrakube_api      = 28081
      terrakube_registry = 28082
      terrakube_dex      = 28083
      semaphore_web      = 28084
    }
  }
}

# --- internal_src joining ---

run "single_network_no_comma_in_src" {
  command = plan

  variables {
    internal_networks = ["192.168.0.0/16"]
  }

  assert {
    condition     = local.internal_src == "192.168.0.0/16"
    error_message = "Single network should be the source as-is, got '${local.internal_src}'"
  }
}

run "three_networks_comma_joined_src" {
  command = plan

  variables {
    internal_networks = ["192.168.10.0/24", "192.168.20.0/24", "192.168.30.0/24"]
  }

  assert {
    condition     = local.internal_src == "192.168.10.0/24,192.168.20.0/24,192.168.30.0/24"
    error_message = "Three networks must be comma-joined, got '${local.internal_src}'"
  }
}

# --- Rule counts independent of network count ---

run "syslog_rules_always_four" {
  command = plan

  variables {
    internal_networks = ["192.168.10.0/24", "192.168.20.0/24", "192.168.30.0/24"]
  }

  # UDP 514-518, TCP 514-518, UDP 1514-1518, TCP 1514-1518
  assert {
    condition     = length(local.syslog_rules) == 4
    error_message = "syslog_rules must be exactly 4 (2 protocols × 2 port groups), got ${length(local.syslog_rules)}"
  }
}

run "pipeline_services_rules_always_three" {
  command = plan

  variables {
    internal_networks = ["192.168.10.0/24", "192.168.20.0/24", "192.168.30.0/24"]
  }

  # HAProxy stats (8404) + Cribl Edge API (9420) + Cribl Edge HEC input (8088) + Cribl S2S frontend (10300)
  assert {
    condition     = length(local.pipeline_services_rules) == 4
    error_message = "pipeline_services_rules must be exactly 4, got ${length(local.pipeline_services_rules)}"
  }
}

run "netflow_rules_always_one" {
  command = plan

  variables {
    internal_networks = ["192.168.10.0/24", "192.168.20.0/24", "192.168.30.0/24"]
  }

  assert {
    condition     = length(local.netflow_rules) == 1
    error_message = "netflow_rules must be exactly 1 (UDP 2055), got ${length(local.netflow_rules)}"
  }
}

run "outbound_rules_always_three" {
  command = plan

  variables {
    internal_networks = ["192.168.10.0/24", "192.168.20.0/24", "192.168.30.0/24"]
  }

  # TCP + UDP + ICMP outbound
  assert {
    condition     = length(local.outbound_internal_rules) == 3
    error_message = "outbound_internal_rules must be exactly 3 (TCP, UDP, ICMP), got ${length(local.outbound_internal_rules)}"
  }
}

run "cribl_stream_rules_always_one" {
  command = plan

  variables {
    internal_networks = ["192.168.10.0/24", "192.168.20.0/24", "192.168.30.0/24"]
  }

  # Cribl Stream API (9000) + Cribl S2S input (10300) + Prometheus remote_write (9201)
  assert {
    condition     = length(local.cribl_stream_services_rules) == 3
    error_message = "cribl_stream_services_rules must be exactly 3, got ${length(local.cribl_stream_services_rules)}"
  }
}

run "ntp_server_rules_always_one" {
  command = plan

  variables {
    internal_networks = ["192.168.10.0/24", "192.168.20.0/24", "192.168.30.0/24"]
  }

  assert {
    condition     = length(local.ntp_server_rules) == 1
    error_message = "ntp_server_rules must be exactly 1 (UDP 123), got ${length(local.ntp_server_rules)}"
  }
}

run "syslog_rules_source_matches_joined_networks" {
  command = plan

  variables {
    internal_networks = ["192.168.10.0/24", "192.168.20.0/24"]
  }

  assert {
    condition     = local.syslog_rules[0].source == "192.168.10.0/24,192.168.20.0/24"
    error_message = "syslog_rules source must be comma-joined networks, got '${local.syslog_rules[0].source}'"
  }
}

# --- DRY: rule dports are sourced from var.pipeline_constants, not literals ---

run "object_storage_rules_track_constants_port" {
  command = plan

  variables {
    internal_networks = ["192.168.0.0/16"]
  }

  assert {
    condition     = local.s3_services_rules[0].dport == tostring(var.pipeline_constants.service_ports.object_storage_s3)
    error_message = "s3_services_rules[0].dport must be tostring(pipeline_constants.service_ports.object_storage_s3), got '${local.s3_services_rules[0].dport}'"
  }

  assert {
    condition     = local.s3_services_rules[1].dport == tostring(var.pipeline_constants.service_ports.object_storage_console)
    error_message = "s3_services_rules[1].dport must be tostring(pipeline_constants.service_ports.object_storage_console), got '${local.s3_services_rules[1].dport}'"
  }
}

run "notification_rules_track_constants_ports" {
  command = plan

  variables {
    internal_networks = ["192.168.0.0/16"]
  }

  assert {
    condition     = local.notification_services_rules[0].dport == tostring(var.pipeline_constants.notification_ports.mailpit_smtp)
    error_message = "notification rule 0 must track mailpit_smtp constant, got '${local.notification_services_rules[0].dport}'"
  }

  assert {
    condition     = local.notification_services_rules[2].dport == tostring(var.pipeline_constants.notification_ports.ntfy_http)
    error_message = "notification rule 2 must track ntfy_http constant, got '${local.notification_services_rules[2].dport}'"
  }
}

# --- Newly-promoted literals all track pipeline_constants ---

run "syslog_rules_track_constants_ports" {
  command = plan

  variables {
    internal_networks = ["192.168.0.0/16"]
  }

  # Standard app-facing frontends derived from syslog_port_map.*.standard
  assert {
    condition     = local.syslog_rules[0].dport == "514,515,516,517,518"
    error_message = "syslog_rules[0].dport must be the derived standard 514-518 list, got '${local.syslog_rules[0].dport}'"
  }

  assert {
    condition     = local.syslog_rules[1].dport == "514,515,516,517,518"
    error_message = "syslog_rules[1].dport must be the derived standard 514-518 list, got '${local.syslog_rules[1].dport}'"
  }

  # Pipeline backends derived from syslog_port_map.*.high
  assert {
    condition     = local.syslog_rules[2].dport == "1514,1515,1516,1517,1518"
    error_message = "syslog_rules[2].dport must be the derived 1514:1518 range, got '${local.syslog_rules[2].dport}'"
  }

  assert {
    condition     = local.syslog_rules[3].dport == "1514,1515,1516,1517,1518"
    error_message = "syslog_rules[3].dport must be the derived 1514:1518 range, got '${local.syslog_rules[3].dport}'"
  }
}

run "splunk_forwarding_rule_tracks_constant" {
  command = plan

  variables {
    internal_networks = ["192.168.0.0/16"]
  }

  assert {
    condition     = local.splunk_services_rules[2].dport == tostring(var.pipeline_constants.service_ports.splunk_forwarding)
    error_message = "splunk_services_rules[2].dport must equal tostring(service_ports.splunk_forwarding), got '${local.splunk_services_rules[2].dport}'"
  }
}

run "ntp_rule_tracks_constant" {
  command = plan

  variables {
    internal_networks = ["192.168.0.0/16"]
  }

  assert {
    condition     = local.ntp_server_rules[0].dport == tostring(var.pipeline_constants.service_ports.ntp)
    error_message = "ntp_server_rules[0].dport must equal tostring(service_ports.ntp), got '${local.ntp_server_rules[0].dport}'"
  }
}

run "ai_terrakube_egress_tracks_constants_and_has_no_wan" {
  command = plan

  variables {
    internal_networks = ["192.168.0.0/16"]
  }

  # Terrakube API/registry + RustFS S3 ports derive from constants (no literals).
  assert {
    condition     = local.ai_terrakube_egress_rules[4].dport == tostring(var.pipeline_constants.iac_platform_ports.terrakube_api)
    error_message = "ai_terrakube_egress_rules[4].dport must equal tostring(iac_platform_ports.terrakube_api), got '${local.ai_terrakube_egress_rules[4].dport}'"
  }

  assert {
    condition     = local.ai_terrakube_egress_rules[5].dport == tostring(var.pipeline_constants.iac_platform_ports.terrakube_registry)
    error_message = "ai_terrakube_egress_rules[5].dport must equal tostring(iac_platform_ports.terrakube_registry), got '${local.ai_terrakube_egress_rules[5].dport}'"
  }

  assert {
    condition     = local.ai_terrakube_egress_rules[6].dport == tostring(var.pipeline_constants.service_ports.object_storage_s3)
    error_message = "ai_terrakube_egress_rules[6].dport must equal tostring(service_ports.object_storage_s3), got '${local.ai_terrakube_egress_rules[6].dport}'"
  }

  # Every ai-terrakube egress rule targets internal only — no WAN (null dest).
  assert {
    condition     = alltrue([for r in local.ai_terrakube_egress_rules : r.dest == local.internal_src])
    error_message = "ai_terrakube egress must be internal-only (every rule dest == internal_src), no WAN"
  }
}

run "ai_full_net_egress_is_internal_infra_only" {
  command = plan

  variables {
    internal_networks = ["192.168.0.0/16"]
  }

  # ai-full-net internal egress is DNS/NTP/OpenBao only (4 rules); WAN is the
  # separately-attached outbound_https group, not this list.
  assert {
    condition     = length(local.ai_full_net_egress_rules) == 4
    error_message = "ai_full_net_egress_rules must be exactly 4 (DNS udp+tcp, NTP, OpenBao), got ${length(local.ai_full_net_egress_rules)}"
  }

  assert {
    condition     = local.ai_full_net_egress_rules[3].dport == tostring(var.pipeline_constants.service_ports.openbao_api)
    error_message = "ai_full_net_egress_rules[3].dport must equal tostring(service_ports.openbao_api), got '${local.ai_full_net_egress_rules[3].dport}'"
  }

  assert {
    condition     = alltrue([for r in local.ai_full_net_egress_rules : r.dest == local.internal_src])
    error_message = "ai_full_net internal egress must be internal-only (every rule dest == internal_src)"
  }
}

run "idrac_kvm_rules_track_constants_ports" {
  command = plan

  variables {
    internal_networks = ["192.168.0.0/16"]
  }

  assert {
    condition     = local.idrac_kvm_services_rules[0].dport == tostring(var.pipeline_constants.service_ports.idrac_kvm_r410)
    error_message = "idrac_kvm_services_rules[0].dport must equal tostring(service_ports.idrac_kvm_r410), got '${local.idrac_kvm_services_rules[0].dport}'"
  }

  assert {
    condition     = local.idrac_kvm_services_rules[1].dport == tostring(var.pipeline_constants.service_ports.idrac_kvm_r710)
    error_message = "idrac_kvm_services_rules[1].dport must equal tostring(service_ports.idrac_kvm_r710), got '${local.idrac_kvm_services_rules[1].dport}'"
  }
}

run "monitoring_rules_track_constants_ports" {
  command = plan

  variables {
    internal_networks = ["192.168.0.0/16"]
  }

  # SmokePing UI + 4 Prometheus exporters (speedtest, prober, blackbox, atlas) + irtt UDP
  assert {
    condition     = length(local.monitoring_services_rules) == 6
    error_message = "monitoring_services_rules must be exactly 6 (UI + speedtest/prober/blackbox/atlas exporters + irtt), got ${length(local.monitoring_services_rules)}"
  }

  assert {
    condition     = local.monitoring_services_rules[0].dport == tostring(var.pipeline_constants.service_ports.smokeping_web)
    error_message = "monitoring_services_rules[0].dport must track service_ports.smokeping_web, got '${local.monitoring_services_rules[0].dport}'"
  }

  assert {
    condition     = local.monitoring_services_rules[2].dport == tostring(var.pipeline_constants.service_ports.smokeping_prober)
    error_message = "monitoring_services_rules[2].dport must track service_ports.smokeping_prober, got '${local.monitoring_services_rules[2].dport}'"
  }

  assert {
    condition     = local.monitoring_services_rules[3].dport == tostring(var.pipeline_constants.service_ports.blackbox_exporter)
    error_message = "monitoring_services_rules[3].dport must track service_ports.blackbox_exporter, got '${local.monitoring_services_rules[3].dport}'"
  }

  # irtt is the only UDP rule in the monitoring set
  assert {
    condition     = local.monitoring_services_rules[5].proto == "udp" && local.monitoring_services_rules[5].dport == tostring(var.pipeline_constants.service_ports.irtt)
    error_message = "monitoring_services_rules[5] must be UDP irtt, got proto='${local.monitoring_services_rules[5].proto}' dport='${local.monitoring_services_rules[5].dport}'"
  }
}

run "pipeline_syslog_range_excludes_default" {
  command = plan

  variables {
    internal_networks = ["192.168.0.0/16"]
  }

  # 514 (a standard frontend) must NOT appear in the backend list; comma-joined
  # avoids any over-permit if a non-contiguous port is ever added to the map.
  assert {
    condition     = local.pipeline_syslog_range == "1514,1515,1516,1517,1518"
    error_message = "pipeline_syslog_range must exclude the standard ports, got '${local.pipeline_syslog_range}'"
  }

  assert {
    condition     = !contains(local.pipeline_syslog_ports, 514)
    error_message = "pipeline_syslog_ports must not contain the standard port 514, got '${jsonencode(local.pipeline_syslog_ports)}'"
  }
}

run "syslog_standard_range_tracks_port_map" {
  command = plan

  variables {
    internal_networks = ["192.168.0.0/16"]
  }

  assert {
    condition     = local.syslog_standard_range == "514,515,516,517,518"
    error_message = "syslog_standard_range must be the derived 514-518 list, got '${local.syslog_standard_range}'"
  }

  assert {
    condition     = !contains(local.syslog_standard_ports, 1514)
    error_message = "syslog_standard_ports must not contain backend ports, got '${jsonencode(local.syslog_standard_ports)}'"
  }
}

run "honeypot_notify_rule_tracks_constant" {
  command = plan

  variables {
    internal_networks = ["192.168.0.0/16"]
  }

  # The alert gateway exposes exactly its apprise-api REST port.
  assert {
    condition     = length(local.honeypot_notify_services_rules) == 1
    error_message = "honeypot_notify_services_rules must be exactly 1 (apprise_api), got ${length(local.honeypot_notify_services_rules)}"
  }

  assert {
    condition     = local.honeypot_notify_services_rules[0].dport == tostring(var.pipeline_constants.honeypot_ports.apprise_api)
    error_message = "honeypot_notify rule must track honeypot_ports.apprise_api, got '${local.honeypot_notify_services_rules[0].dport}'"
  }
}

run "honeypot_decoy_rules_track_constants_and_split_proto" {
  command = plan

  variables {
    internal_networks = ["192.168.10.0/24", "192.168.20.0/24"]
  }

  # First decoy rule is FTP (TCP), sourced from the comma-joined internal nets.
  assert {
    condition     = local.honeypot_services_rules[0].dport == tostring(var.pipeline_constants.honeypot_ports.ftp) && local.honeypot_services_rules[0].proto == "tcp"
    error_message = "honeypot decoy rule 0 must be TCP ftp, got proto='${local.honeypot_services_rules[0].proto}' dport='${local.honeypot_services_rules[0].dport}'"
  }

  assert {
    condition     = local.honeypot_services_rules[0].source == "192.168.10.0/24,192.168.20.0/24"
    error_message = "honeypot decoy rule source must be comma-joined networks, got '${local.honeypot_services_rules[0].source}'"
  }

  # The UDP decoys (SNMP/SIP/TFTP/NTP) must be present so OpenCanary's UDP
  # modules are reachable — assert at least one udp rule exists.
  assert {
    condition     = length([for r in local.honeypot_services_rules : r if r.proto == "udp"]) == 4
    error_message = "honeypot_services_rules must include exactly 4 UDP decoys (snmp/sip/tftp/ntp), got ${length([for r in local.honeypot_services_rules : r if r.proto == "udp"])}"
  }
}

run "ai_log_ingest_rules_track_constants" {
  command = plan

  variables {
    internal_networks = ["192.168.10.0/24", "192.168.20.0/24"]
  }

  # One TCP rule per ai_log_ports entry (9 here), all sourced from the joined nets.
  assert {
    condition     = length(local.ai_log_ingest_rules) == length(var.pipeline_constants.ai_log_ports)
    error_message = "ai_log_ingest_rules must have one rule per ai_log_ports entry, got ${length(local.ai_log_ingest_rules)}"
  }

  assert {
    condition     = alltrue([for r in local.ai_log_ingest_rules : r.proto == "tcp"])
    error_message = "all ai_log_ingest_rules must be TCP"
  }

  assert {
    condition     = alltrue([for r in local.ai_log_ingest_rules : r.source == "192.168.10.0/24,192.168.20.0/24"])
    error_message = "ai_log_ingest_rules source must be the comma-joined internal networks"
  }

  # dports track the constants map exactly (no literals).
  assert {
    condition     = alltrue([for r in local.ai_log_ingest_rules : contains([for p in values(var.pipeline_constants.ai_log_ports) : tostring(p)], r.dport)])
    error_message = "every ai_log_ingest rule dport must come from pipeline_constants.ai_log_ports"
  }
}

run "outbound_https_is_tcp_443_only" {
  command = plan

  variables {
    internal_networks = ["192.168.0.0/16"]
  }

  # Explicitly attached workload egress stays the single TCP/443 rule — any
  # growth here widens internet egress and needs explicit review.
  assert {
    condition     = length(local.outbound_https_rules) == 1
    error_message = "outbound_https_rules must contain exactly one rule, got ${length(local.outbound_https_rules)}"
  }

  assert {
    condition     = local.outbound_https_rules[0].proto == "tcp" && local.outbound_https_rules[0].dport == "443"
    error_message = "outbound_https_rules[0] must be TCP 443, got proto='${local.outbound_https_rules[0].proto}' dport='${local.outbound_https_rules[0].dport}'"
  }
}

run "outbound_http_is_tcp_80_only" {
  command = plan
  module {
    source = "./"
  }
  variables {
    node_name         = "pve1"
    internal_networks = ["10.0.0.0/8"]
  }

  assert {
    condition     = length(local.outbound_http_rules) == 1
    error_message = "outbound_http_rules must contain exactly one rule, got ${length(local.outbound_http_rules)}"
  }

  assert {
    condition     = local.outbound_http_rules[0].proto == "tcp" && local.outbound_http_rules[0].dport == "80"
    error_message = "outbound_http_rules[0] must be TCP 80, got proto='${local.outbound_http_rules[0].proto}' dport='${local.outbound_http_rules[0].dport}'"
  }
}

run "openbao_receives_outbound_https" {
  command = plan

  variables {
    openbao_container_ids = { openbao = 130 }
  }

  assert {
    condition = contains(
      [for rule in proxmox_virtual_environment_firewall_rules.openbao_container["openbao"].rule : rule.security_group],
      proxmox_virtual_environment_cluster_firewall_security_group.outbound_https.name,
    )
    error_message = "OpenBao containers must attach the outbound-https security group"
  }
}

run "node_exporter_rule_tracks_constant_and_siem_scope" {
  command = plan

  variables {
    internal_networks = ["192.168.10.0/24", "192.168.20.0/24"]
    network_cidrs     = { siem = "192.168.40.0/24" }
  }

  assert {
    condition     = length(local.node_exporter_rules) == 1
    error_message = "node_exporter_rules must be exactly 1 (TCP 9100), got ${length(local.node_exporter_rules)}"
  }

  assert {
    condition     = local.node_exporter_rules[0].dport == tostring(var.pipeline_constants.service_ports.node_exporter)
    error_message = "node_exporter rule must track service_ports.node_exporter, got '${local.node_exporter_rules[0].dport}'"
  }

  # Scoped to the siem VLAN, NOT internal_src — one consumer for host metrics.
  assert {
    condition     = local.node_exporter_rules[0].source == "192.168.40.0/24"
    error_message = "node_exporter rule source must be the siem CIDR only, got '${local.node_exporter_rules[0].source}'"
  }
}

run "node_exporter_rule_inert_without_siem_cidr" {
  command = plan

  variables {
    internal_networks = ["192.168.0.0/16"]
    network_cidrs     = {}
  }

  assert {
    condition     = local.node_exporter_rules[0].source == ""
    error_message = "node_exporter rule must be inert (empty source) when the siem CIDR is absent"
  }
}

# --- media per-guest web rules ---

run "media_web_rules_track_constants" {
  command = plan

  assert {
    condition     = toset(keys(local.media_web_rules)) == toset(["plex", "radarr", "seerr", "sonarr", "sortarr"])
    error_message = "media_web_rules must cover exactly the five LAN-only media guests (never the VPN-locked downloader)"
  }

  assert {
    condition = alltrue([
      local.media_web_rules.sonarr.dport == tostring(var.pipeline_constants.media_ports.sonarr_web),
      local.media_web_rules.radarr.dport == tostring(var.pipeline_constants.media_ports.radarr_web),
      local.media_web_rules.plex.dport == tostring(var.pipeline_constants.media_ports.plex_web),
      local.media_web_rules.seerr.dport == tostring(var.pipeline_constants.media_ports.seerr_web),
      local.media_web_rules.sortarr.dport == tostring(var.pipeline_constants.media_ports.sortarr_web),
    ])
    error_message = "media per-guest web dports drifted from pipeline_constants.media_ports"
  }

  assert {
    condition = !anytrue([
      contains(values(local.media_web_rules)[*].dport, tostring(var.pipeline_constants.media_ports.qbittorrent_web)),
      contains(values(local.media_web_rules)[*].dport, tostring(var.pipeline_constants.media_ports.prowlarr_web)),
    ])
    error_message = "downloader-resident ports (qBittorrent/Prowlarr) must never appear on the LAN-only media guests"
  }
}

# --- postgres + nautobot service rules (issue #138) ---

run "postgres_rule_tracks_constant_and_internal_scope" {
  command = plan

  variables {
    internal_networks = ["192.168.10.0/24", "192.168.20.0/24"]
  }

  # Exactly one live rule: TCP 5432 from the comma-joined internal networks.
  assert {
    condition     = length(local.postgres_services_rules) == 1
    error_message = "postgres_services_rules must be exactly 1 (TCP 5432), got ${length(local.postgres_services_rules)}"
  }

  assert {
    condition     = local.postgres_services_rules[0].proto == "tcp" && local.postgres_services_rules[0].dport == tostring(var.pipeline_constants.service_ports.postgres_default)
    error_message = "postgres rule must be TCP tracking service_ports.postgres_default, got proto='${local.postgres_services_rules[0].proto}' dport='${local.postgres_services_rules[0].dport}'"
  }

  assert {
    condition     = local.postgres_services_rules[0].source == "192.168.10.0/24,192.168.20.0/24"
    error_message = "postgres rule source must be the comma-joined internal networks, got '${local.postgres_services_rules[0].source}'"
  }
}

run "nautobot_rule_tracks_constant_and_internal_scope" {
  command = plan

  variables {
    internal_networks = ["192.168.10.0/24", "192.168.20.0/24"]
  }

  # Exactly one live rule: TCP nautobot_web (8080) from the internal networks.
  assert {
    condition     = length(local.nautobot_services_rules) == 1
    error_message = "nautobot_services_rules must be exactly 1 (TCP nautobot_web), got ${length(local.nautobot_services_rules)}"
  }

  assert {
    condition     = local.nautobot_services_rules[0].proto == "tcp" && local.nautobot_services_rules[0].dport == tostring(var.pipeline_constants.service_ports.nautobot_web)
    error_message = "nautobot rule must be TCP tracking service_ports.nautobot_web, got proto='${local.nautobot_services_rules[0].proto}' dport='${local.nautobot_services_rules[0].dport}'"
  }
}

# --- authelia service rules ---

run "authelia_rule_tracks_constant_and_internal_scope" {
  command = plan

  variables {
    internal_networks = ["192.168.10.0/24", "192.168.20.0/24"]
  }

  # Exactly one live rule: TCP authelia_portal (9091) from the internal networks.
  assert {
    condition     = length(local.authelia_services_rules) == 1
    error_message = "authelia_services_rules must be exactly 1 (TCP authelia_portal), got ${length(local.authelia_services_rules)}"
  }

  assert {
    condition     = local.authelia_services_rules[0].proto == "tcp" && local.authelia_services_rules[0].dport == tostring(var.pipeline_constants.service_ports.authelia_portal)
    error_message = "authelia rule must be TCP tracking service_ports.authelia_portal, got proto='${local.authelia_services_rules[0].proto}' dport='${local.authelia_services_rules[0].dport}'"
  }

  assert {
    condition     = local.authelia_services_rules[0].source == "192.168.10.0/24,192.168.20.0/24"
    error_message = "authelia rule source must be the comma-joined internal networks, got '${local.authelia_services_rules[0].source}'"
  }
}

# --- vikunja service rules (issue #141) ---

run "vikunja_rule_tracks_constant_and_internal_scope" {
  command = plan

  variables {
    internal_networks = ["192.168.10.0/24", "192.168.20.0/24"]
  }

  # Exactly one live rule: TCP vikunja_web (3456) from the internal networks.
  assert {
    condition     = length(local.vikunja_services_rules) == 1
    error_message = "vikunja_services_rules must be exactly 1 (TCP vikunja_web), got ${length(local.vikunja_services_rules)}"
  }

  assert {
    condition     = local.vikunja_services_rules[0].proto == "tcp" && local.vikunja_services_rules[0].dport == tostring(var.pipeline_constants.service_ports.vikunja_web)
    error_message = "vikunja rule must be TCP tracking service_ports.vikunja_web, got proto='${local.vikunja_services_rules[0].proto}' dport='${local.vikunja_services_rules[0].dport}'"
  }

  assert {
    condition     = local.vikunja_services_rules[0].source == "192.168.10.0/24,192.168.20.0/24"
    error_message = "vikunja rule source must be the comma-joined internal networks, got '${local.vikunja_services_rules[0].source}'"
  }
}
