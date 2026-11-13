# Tests for roster-agent firewall edge cases.

mock_provider "proxmox" {}

variables {
  node_name                      = "node-example"
  management_network             = "192.0.2.0/24"
  splunk_network                 = "192.0.2.200"
  internal_networks              = ["192.0.2.0/24"]
  ai_network                     = "198.51.100.0/24"
  llm_router_trusted_src         = "192.0.2.7,192.0.2.8,192.0.2.30"
  prometheus_scraper_trusted_src = "192.0.2.30"
  pipeline_constants = {
    service_ports = {
      haproxy_stats             = 8404, splunk_web = 8000, splunk_hec = 8088, splunk_mgmt = 8089
      splunk_forwarding         = 9997, cribl_edge_api = 9420, cribl_stream_api = 9000
      cribl_s2s                 = 10300, cribl_s2s_metrics = 10360, cribl_pve_metrics = 10370
      cribl_prometheus_rw       = 9201, apt_cacher_ng = 3142, squid_proxy = 3128
      pypi_cache                = 3141, npm_cache = 4873, raw_cache = 8081
      object_storage_s3         = 9000, object_storage_console = 9001, openbao_api = 8200
      openbao_cluster           = 8201, postgres_default = 5432, redis_default = 6379
      nautobot_web              = 8080, vikunja_web = 3456, homebox_web = 7745, homarr_web = 7575, homepage_web = 3000
      youtrack_web              = 8080, leantime_web = 80
      glance_web                = 8080, wall_web = 8080, gatus_web = 8080, uptime_kuma_web = 3001
      grafana_web               = 3000, victoriametrics = 8428, vmauth = 8427, authelia_portal = 9091, zammad_web = 8080
      mcp_gateway_web           = 4444, ntp = 123, idrac_kvm_r410 = 5410, idrac_kvm_r710 = 5710
      smokeping_web             = 80, speedtest_exporter = 9798, smokeping_prober = 9374
      blackbox_exporter         = 9115, atlas_exporter = 9400, dcgm_exporter = 9400, irtt = 2112, node_exporter = 9100, zfs_exporter = 9134
      llm_fast_api              = 10434, llm_gpu_serving_api = 10440, llm_fast_trial_api = 10436, llm_classify_api = 8000, llm_router_api = 4000, agentgateway_proxy = 8080
      agentgateway_admin        = 15000, agentgateway_metrics = 15020, hermes_webhook = 8644
      hermes_api                = 8642, hermes_a2a = 9901, hermes_dashboard = 8080, hermes_ui_workspace = 3000
      hermes_ui_mission_control = 3001, herdr_relay_ws = 8375, orca_server = 6768, hermes_webui = 8787
      hermes_studio             = 8648, n8n_web = 5678, crawl4ai_api = 11235, hatchet_web = 8090, hatchet_grpc = 7072, hatchet_health = 8733
      dify_web                  = 80, langflow_web = 7860
      langfuse_web              = 3000, phoenix_web = 6006, phoenix_grpc = 4317, phoenix_metrics = 9090
      phoenix_postgres_exporter = 9187
      clickhouse_http           = 8123, clickhouse_native = 9000, clickhouse_metrics = 9363, langgraph_api = 8124
      agent_chat_ui_web         = 3000, docling_serve_api = 5001, otel_traces_grpc = 4317
      otel_traces_http          = 4318, otel_metrics_grpc = 4327, otel_metrics_http = 4328
      otel_logs_grpc            = 4337, otel_logs_http = 4338
    }
    syslog_ports = { default = 514, unifi = 1514, palo_alto = 1515, cisco_asa = 1516, linux = 1517, windows = 1518 }
    syslog_port_map = {
      unifi     = { standard = 514, high = 1514, index = "unifi", sourcetype = "ubiquiti:unifi" }
      palo_alto = { standard = 515, high = 1515, index = "firewall", sourcetype = "pan:firewall" }
      cisco_asa = { standard = 516, high = 1516, index = "firewall", sourcetype = "cisco:asa" }
      linux     = { standard = 517, high = 1517, index = "os", sourcetype = "syslog" }
      windows   = { standard = 518, high = 1518, index = "os", sourcetype = "syslog" }
    }
    netflow_ports      = { unifi = 2055 }
    notification_ports = { mailpit_smtp = 1025, mailpit_web = 8025, ntfy_http = 8080 }
    vector_db_ports    = { qdrant_http = 6333, qdrant_grpc = 6334 }
    memory_ports       = { hindsight_api = 8888, hindsight_cp = 9999 }
    extract_ports      = { firecrawl_api = 3002 }
    ai_log_ports = {
      claude_code   = 10311, codex_cli = 10312, agy_cli = 10313, copilot_cli = 10314
      vscode        = 10315, macstudio_llm = 10321, macstudio_gate = 10322, homelab_llm = 10323
      openbao_audit = 10331
    }
    media_ports = {
      qbittorrent_web = 8080, prowlarr_web = 9696, sonarr_web = 8989, radarr_web = 7878
      plex_web        = 32400, seerr_web = 5055, sortarr_web = 8787
    }
    honeypot_ports = {
      apprise_api = 8000, ftp = 21, telnet = 23, http = 80, https = 443, smb = 445
      tftp        = 69, snmp = 161, ntp = 123, sip = 5060, mssql = 1433, mysql = 3306
      postgres    = 5432, rdp = 3389, vnc = 5900, redis = 6379, git = 9418, http_proxy = 8080
    }
    iac_platform_ports = {
      terrakube_ui  = 28080, terrakube_api = 28081, terrakube_registry = 28082
      terrakube_dex = 28083, semaphore_web = 28084
    }
  }
}

run "empty_agent_roster_ignores_populated_system_catalogs" {
  command = plan

  variables {
    agent_ingress_vip = "192.0.2.9"
    agent_system_ports = {
      splunk = [8089, 8000]
      cribl  = [9000]
    }
    agent_system_hosts = {
      splunk = ["192.0.2.200", "192.0.2.201"]
      cribl  = ["192.0.2.202"]
    }
  }

  assert {
    condition = (
      length(var.agent_system_ports) == 2 &&
      length(var.agent_system_hosts) == 2 &&
      length(proxmox_virtual_environment_firewall_options.agent_container) == 0 &&
      length(proxmox_virtual_environment_firewall_rules.agent_container) == 0 &&
      length(proxmox_virtual_environment_cluster_firewall_security_group.agent_owned_system) == 0 &&
      length(proxmox_virtual_environment_cluster_firewall_security_group.agent_ingress_https) == 0 &&
      length(proxmox_virtual_environment_cluster_firewall_security_group.hermes_agent_deny_owned_systems) == 0
    )
    error_message = "An empty roster must create no agent firewall objects with populated system catalogs."
  }
}

run "agent_owned_ports_must_not_overlap_shared_ai_egress" {
  command = plan

  variables {
    agent_ingress_vip  = "192.0.2.9"
    agent_system_ports = { cribl = [10311] }
    agent_system_hosts = { cribl = ["198.51.100.20"] }
    agent_containers = {
      "research-scout" = { vm_id = 240, owns = ["cribl"] }
    }
  }

  expect_failures = [proxmox_virtual_environment_firewall_rules.agent_container["research-scout"]]
}

run "agent_container_resolves_the_placement_node_per_guest" {
  command = plan

  variables {
    agent_ingress_vip = "192.0.2.9"
    agent_containers = {
      "placed-agent"   = { vm_id = 240, owns = [] }
      "unlisted-agent" = { vm_id = 241, owns = [] }
    }
    container_nodes = {
      "240" = "node-two"
    }
  }

  assert {
    condition     = proxmox_virtual_environment_firewall_options.agent_container["placed-agent"].node_name == "node-two" && proxmox_virtual_environment_firewall_rules.agent_container["placed-agent"].node_name == "node-two"
    error_message = "An agent container whose VM ID is in container_nodes must get its firewall options and rules on that node."
  }

  assert {
    condition     = proxmox_virtual_environment_firewall_options.agent_container["unlisted-agent"].node_name == var.node_name && proxmox_virtual_environment_firewall_rules.agent_container["unlisted-agent"].node_name == var.node_name
    error_message = "An agent container whose VM ID is absent from container_nodes must keep the stack node_name."
  }
}

run "pepper_uses_proxied_egress_and_plain_hermes_keeps_its_rules" {
  command = plan

  variables {
    hermes_agent_container_ids  = { pepper = 240, plain = 241 }
    hermes_pepper_container_ids = { pepper = 240 }
    package_cache_destinations  = ["cache-guest-primary", "cache-guest-secondary"]
    container_nodes             = { "240" = "node-two" }
  }

  assert {
    condition = [for rule in proxmox_virtual_environment_firewall_rules.hermes_agent_container["pepper"].rule : rule.security_group] == [
      proxmox_virtual_environment_cluster_firewall_security_group.internal_access.name,
      proxmox_virtual_environment_cluster_firewall_security_group.ai_proxied_egress.name,
      proxmox_virtual_environment_cluster_firewall_security_group.package_cache_egress["active"].name,
      proxmox_virtual_environment_cluster_firewall_security_group.hermes_webhook_services.name,
    ]
    error_message = "Pepper must retain Hermes inbound services and attach only proxied and package-cache egress, without outbound_internal or outbound_https."
  }

  assert {
    condition = (
      toset([for rule in proxmox_virtual_environment_cluster_firewall_security_group.package_cache_egress["active"].rule : rule.dport]) == toset([
        tostring(var.pipeline_constants.service_ports.pypi_cache),
        tostring(var.pipeline_constants.service_ports.npm_cache),
        tostring(var.pipeline_constants.service_ports.raw_cache),
      ]) &&
      alltrue([for rule in proxmox_virtual_environment_cluster_firewall_security_group.package_cache_egress["active"].rule : rule.dest == join(",", var.package_cache_destinations) && rule.dest != join(",", var.internal_networks)])
    )
    error_message = "Pepper package-cache egress must allow exactly the three cache ports to the cache guests only."
  }

  assert {
    condition = (
      proxmox_virtual_environment_firewall_options.hermes_agent_container["pepper"].enabled &&
      proxmox_virtual_environment_firewall_options.hermes_agent_container["pepper"].input_policy == "DROP" &&
      proxmox_virtual_environment_firewall_options.hermes_agent_container["pepper"].output_policy == "DROP" &&
      proxmox_virtual_environment_firewall_options.hermes_agent_container["pepper"].dhcp &&
      proxmox_virtual_environment_firewall_options.hermes_agent_container["pepper"].node_name == "node-two" &&
      proxmox_virtual_environment_firewall_rules.hermes_agent_container["pepper"].node_name == "node-two"
    )
    error_message = "Pepper must keep enabled default-deny policies, DHCP, and per-guest placement."
  }

  assert {
    condition = [for rule in proxmox_virtual_environment_firewall_rules.hermes_agent_container["plain"].rule : rule.security_group] == [
      proxmox_virtual_environment_cluster_firewall_security_group.internal_access.name,
      proxmox_virtual_environment_cluster_firewall_security_group.outbound_internal.name,
      proxmox_virtual_environment_cluster_firewall_security_group.outbound_https.name,
      proxmox_virtual_environment_cluster_firewall_security_group.hermes_webhook_services.name,
    ]
    error_message = "A plain Hermes guest must keep its existing group list and order alongside Pepper."
  }
}
