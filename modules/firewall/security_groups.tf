# =============================================================================
# Cluster-Level Security Groups (defined once, used by all VMs/containers)
# =============================================================================

resource "proxmox_virtual_environment_cluster_firewall_security_group" "internal_access" {
  name    = "internal-access"
  comment = "Allow SSH and ICMP from internal RFC1918 networks"

  dynamic "rule" {
    for_each = local.internal_access_rules
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

resource "proxmox_virtual_environment_cluster_firewall_security_group" "splunk_services" {
  name    = "splunk-services"
  comment = "Splunk ports accessible from internal RFC1918 networks"

  dynamic "rule" {
    for_each = local.splunk_services_rules
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

resource "proxmox_virtual_environment_cluster_firewall_security_group" "syslog" {
  name    = "syslog"
  comment = "Syslog ports: standard frontends (514-518) and pipeline backends (1514-1518) from internal networks"

  dynamic "rule" {
    for_each = local.syslog_rules
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

resource "proxmox_virtual_environment_cluster_firewall_security_group" "pipeline_services" {
  name    = "pipeline-services"
  comment = "Pipeline management: HAProxy stats (8404) and Cribl Edge API (9000) from internal networks"

  dynamic "rule" {
    for_each = local.pipeline_services_rules
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

resource "proxmox_virtual_environment_cluster_firewall_security_group" "netflow" {
  name    = "netflow"
  comment = "NetFlow/IPFIX UDP port 2055 from internal networks"

  dynamic "rule" {
    for_each = local.netflow_rules
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

# Splunk cluster communication - uses var.splunk_network, not internal_networks
# Kept as static rules (only 3 rules, no DRY benefit from data-driving)
resource "proxmox_virtual_environment_cluster_firewall_security_group" "splunk_cluster" {
  name    = "splunk-cluster"
  comment = "Splunk cluster ports (management, replication, clustering)"

  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = "8089"
    source  = var.splunk_network
    comment = "Splunk management from cluster"
  }

  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = "8080"
    source  = var.splunk_network
    comment = "Splunk replication from cluster"
  }

  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = "9887"
    source  = var.splunk_network
    comment = "Splunk clustering from cluster"
  }
}

resource "proxmox_virtual_environment_cluster_firewall_security_group" "outbound_internal" {
  name    = "outbound-internal"
  comment = "Allow outbound to RFC1918 only (blocks internet)"

  dynamic "rule" {
    for_each = local.outbound_internal_rules
    content {
      type    = "out"
      action  = "ACCEPT"
      proto   = rule.value.proto
      dest    = rule.value.dest
      comment = rule.value.comment
    }
  }

  # Splunk cluster outbound - static rules using var.splunk_network
  rule {
    type    = "out"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = "8089"
    dest    = var.splunk_network
    comment = "Outbound Splunk management"
  }

  rule {
    type    = "out"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = "8080"
    dest    = var.splunk_network
    comment = "Outbound Splunk replication"
  }

  rule {
    type    = "out"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = "9887"
    dest    = var.splunk_network
    comment = "Outbound Splunk clustering"
  }
}

resource "proxmox_virtual_environment_cluster_firewall_security_group" "outbound_https" {
  name    = "outbound-https"
  comment = "Allow outbound HTTPS (TCP 443) to any destination for explicitly attached workloads (see locals.outbound_https_rules)"

  dynamic "rule" {
    for_each = local.outbound_https_rules
    content {
      type    = "out"
      action  = "ACCEPT"
      proto   = rule.value.proto
      dport   = rule.value.dport
      dest    = rule.value.dest
      comment = rule.value.comment
    }
  }
}

resource "proxmox_virtual_environment_cluster_firewall_security_group" "outbound_http" {
  name    = "outbound-http"
  comment = "Allow outbound HTTP (TCP 80) to any destination for explicitly attached workloads (see locals.outbound_http_rules)"

  dynamic "rule" {
    for_each = local.outbound_http_rules
    content {
      type    = "out"
      action  = "ACCEPT"
      proto   = rule.value.proto
      dport   = rule.value.dport
      dest    = rule.value.dest
      comment = rule.value.comment
    }
  }
}

resource "proxmox_virtual_environment_cluster_firewall_security_group" "notification_services" {
  name    = "notification-svc"
  comment = "Notification service ports: Mailpit SMTP (1025), Mailpit Web (8025), ntfy HTTP (8080) from internal networks"

  dynamic "rule" {
    for_each = local.notification_services_rules
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

resource "proxmox_virtual_environment_cluster_firewall_security_group" "vectordb_services" {
  name    = "vectordb-svc"
  comment = "Vector database ports: Qdrant HTTP (6333) and gRPC (6334) from internal networks"

  dynamic "rule" {
    for_each = local.vectordb_services_rules
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

resource "proxmox_virtual_environment_cluster_firewall_security_group" "cribl_stream_services" {
  name    = "cribl-stream-svc"
  comment = "Cribl Stream API (9000) from internal networks"

  dynamic "rule" {
    for_each = local.cribl_stream_services_rules
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

resource "proxmox_virtual_environment_cluster_firewall_security_group" "apt_cacher_ng_services" {
  name    = "apt-cacher-ng-svc"
  comment = "APT caching proxy port: apt-cacher-ng (3142) from internal networks"

  dynamic "rule" {
    for_each = local.apt_cacher_ng_services_rules
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

resource "proxmox_virtual_environment_cluster_firewall_security_group" "s3_services" {
  name    = "object-storage-svc"
  comment = "Object storage (RustFS): S3 API (${local.svc_ports.object_storage_s3}) and Console (${local.svc_ports.object_storage_console}) from internal networks"

  dynamic "rule" {
    for_each = local.s3_services_rules
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

resource "proxmox_virtual_environment_cluster_firewall_security_group" "openbao_services" {
  name    = "openbao-svc"
  comment = "OpenBao API/UI (8200) and Raft cluster (8201) from internal networks (Traefik front-ends TLS termination on its own ports)"

  dynamic "rule" {
    for_each = local.openbao_services_rules
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

resource "proxmox_virtual_environment_cluster_firewall_security_group" "ntp_server" {
  name    = "ntp-server"
  comment = "NTP server (UDP 123) from internal networks — Proxmox hosts serve time to VMs/containers via chrony"

  dynamic "rule" {
    for_each = local.ntp_server_rules
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

resource "proxmox_virtual_environment_cluster_firewall_security_group" "idrac_kvm_svc" {
  name    = "idrac-kvm-svc"
  comment = "iDRAC KVM HTML5 noVNC ports (5410, 5710) from internal networks"

  dynamic "rule" {
    for_each = local.idrac_kvm_services_rules
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

# honeypot_services + honeypot_notify_services groups are in honeypot_rules.tf (size gate).

resource "proxmox_virtual_environment_cluster_firewall_security_group" "monitoring_services" {
  name    = "monitoring-svc"
  comment = "Network-quality monitoring: SmokePing UI + Prometheus exporters (speedtest, smokeping_prober, blackbox, atlas) + irtt UDP, from internal networks"

  dynamic "rule" {
    for_each = local.monitoring_services_rules
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
