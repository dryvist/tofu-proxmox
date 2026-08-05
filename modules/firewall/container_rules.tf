# Splunk container firewall resources live in modules/firewall/splunk_container_rules.tf
# Pipeline container firewall resources live in modules/firewall/pipeline_container_rules.tf
# (both extracted so container_rules.tf stays under the shared _file-size
# workflow's 12 KB error threshold — same reason s3_rules.tf was split out).

# Cribl Stream containers (receives from Edge, routes to Splunk HEC)

resource "proxmox_virtual_environment_firewall_options" "cribl_stream_container" {
  for_each = var.cribl_stream_container_ids

  node_name     = var.node_name
  container_id  = each.value
  enabled       = local.firewall_defaults.enabled
  input_policy  = local.firewall_defaults.input_policy
  output_policy = local.firewall_defaults.output_policy
  log_level_in  = local.firewall_defaults.log_level_in
  log_level_out = local.firewall_defaults.log_level_out

  depends_on = [proxmox_virtual_environment_cluster_firewall.main]
}

resource "proxmox_virtual_environment_firewall_rules" "cribl_stream_container" {
  for_each = var.cribl_stream_container_ids

  node_name    = var.node_name
  container_id = each.value

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.internal_access.name
    comment        = "Internal access (SSH, ICMP)"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.cribl_stream_services.name
    comment        = "Cribl Stream API (9000)"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.syslog.name
    comment        = "Syslog ingestion (TCP/UDP 514, 1514-1518)"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.netflow.name
    comment        = "NetFlow/IPFIX ingestion (UDP 2055)"
  }

  # HAProxy balances every ai_log_routing frontend PORT-TO-PORT onto this
  # pair (backend ai_backend_<port> -> stream:<port>), so the per-source
  # in_ai_* listeners need the same accepts the HAProxy frontends carry.
  # Without this every AI family except the 10300 S2S path is dropped here
  # while HAProxy's tcp-check marks the backend down and resets senders.
  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.ai_log_ingest.name
    comment        = "AI/LLM log-ingest backends (HAProxy -> per-port in_ai_* listeners)"
  }

  # OTLP trace ingest. The OTLP listener lives on Stream, not Edge — trace
  # fan-out (Splunk plus the LLM-observability backend) consolidated here and
  # the Edge input was removed. The accept did not move with it, so exporters
  # resolved the right host, connected to nothing, and retried until their
  # batches aged out. That failure is invisible from both ends: an OTLP
  # exporter reports export failure only in its own service log, and a
  # listener nothing reaches has nothing to log.
  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.otlp_ingest.name
    comment        = "OTLP trace ingest (producers -> in_otel listener)"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.outbound_internal.name
    comment        = "Outbound to internal only (reaches Splunk HEC 8088)"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.outbound_https.name
    comment        = "Outbound HTTPS (Cribl license telemetry)"
  }

  depends_on = [proxmox_virtual_environment_firewall_options.cribl_stream_container]
}

# Notification containers (Mailpit, ntfy)

resource "proxmox_virtual_environment_firewall_options" "notification_container" {
  for_each = var.notification_container_ids

  node_name     = var.node_name
  container_id  = each.value
  enabled       = local.firewall_defaults.enabled
  input_policy  = local.firewall_defaults.input_policy
  output_policy = "ACCEPT"
  log_level_in  = local.firewall_defaults.log_level_in
  log_level_out = local.firewall_defaults.log_level_out

  depends_on = [proxmox_virtual_environment_cluster_firewall.main]
}

resource "proxmox_virtual_environment_firewall_rules" "notification_container" {
  for_each = var.notification_container_ids

  node_name    = var.node_name
  container_id = each.value

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.internal_access.name
    comment        = "Internal access (SSH, ICMP)"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.notification_services.name
    comment        = "Notification services (Mailpit SMTP/Web, ntfy HTTP)"
  }

  depends_on = [proxmox_virtual_environment_firewall_options.notification_container]
}

# APT caching proxy (apt-cacher-ng — outbound ACCEPT for upstream mirrors)

resource "proxmox_virtual_environment_firewall_options" "apt_cacher_ng_container" {
  for_each = var.apt_cacher_ng_container_ids

  node_name     = var.node_name
  container_id  = each.value
  enabled       = local.firewall_defaults.enabled
  input_policy  = local.firewall_defaults.input_policy
  output_policy = "ACCEPT"
  log_level_in  = local.firewall_defaults.log_level_in
  log_level_out = local.firewall_defaults.log_level_out

  depends_on = [proxmox_virtual_environment_cluster_firewall.main]
}

resource "proxmox_virtual_environment_firewall_rules" "apt_cacher_ng_container" {
  for_each = var.apt_cacher_ng_container_ids

  node_name    = var.node_name
  container_id = each.value

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.internal_access.name
    comment        = "Internal access (SSH, ICMP)"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.apt_cacher_ng_services.name
    comment        = "APT caching proxy (port 3142)"
  }

  depends_on = [proxmox_virtual_environment_firewall_options.apt_cacher_ng_container]
}

# Vector database containers (Qdrant — HTTP 6333, gRPC 6334)

resource "proxmox_virtual_environment_firewall_options" "vectordb_container" {
  for_each = var.vectordb_container_ids

  node_name     = var.node_name
  container_id  = each.value
  enabled       = local.firewall_defaults.enabled
  input_policy  = local.firewall_defaults.input_policy
  output_policy = local.firewall_defaults.output_policy
  log_level_in  = local.firewall_defaults.log_level_in
  log_level_out = local.firewall_defaults.log_level_out

  # DHCP-first guest behind DROP policies (same reason as llm_fabric_rules.tf).
  dhcp = true

  depends_on = [proxmox_virtual_environment_cluster_firewall.main]
}

resource "proxmox_virtual_environment_firewall_rules" "vectordb_container" {
  for_each = var.vectordb_container_ids

  node_name    = var.node_name
  container_id = each.value

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.internal_access.name
    comment        = "Internal access (SSH, ICMP)"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.vectordb_services.name
    comment        = "Vector database (Qdrant HTTP, gRPC)"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.outbound_internal.name
    comment        = "Outbound to internal only"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.outbound_https.name
    comment        = "Outbound HTTPS (Docker install/images)"
  }

  depends_on = [proxmox_virtual_environment_firewall_options.vectordb_container]
}

# RAG engine containers (LlamaIndex — no service ports, outbound-internal only)

resource "proxmox_virtual_environment_firewall_options" "rag_container" {
  for_each = var.rag_container_ids

  node_name     = var.node_name
  container_id  = each.value
  enabled       = local.firewall_defaults.enabled
  input_policy  = local.firewall_defaults.input_policy
  output_policy = local.firewall_defaults.output_policy
  log_level_in  = local.firewall_defaults.log_level_in
  log_level_out = local.firewall_defaults.log_level_out

  # DHCP-first guest behind DROP policies (same reason as llm_fabric_rules.tf).
  dhcp = true

  depends_on = [proxmox_virtual_environment_cluster_firewall.main]
}

resource "proxmox_virtual_environment_firewall_rules" "rag_container" {
  for_each = var.rag_container_ids

  node_name    = var.node_name
  container_id = each.value

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.internal_access.name
    comment        = "Internal access (SSH, ICMP)"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.outbound_internal.name
    comment        = "Outbound to internal only"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.outbound_https.name
    comment        = "Outbound HTTPS (pip/PyPI installs)"
  }

  depends_on = [proxmox_virtual_environment_firewall_options.rag_container]
}

# Object storage container firewall resources: modules/firewall/s3_rules.tf
