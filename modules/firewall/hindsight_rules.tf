# Hindsight agent-memory LXC firewall — two stateless API replicas (hindsight
# tag, ai VLAN) behind a Traefik load-balanced pool. Its security group and
# *_services_rules local live here, not in security_groups.tf /
# locals_rules.tf, to keep those files under the shared _file-size workflow's
# 12 KB gate — same split as postgres_rules.tf.
#
# Live guest-layer rules: the REST API + built-in MCP endpoint (8888) and the
# Control Plane UI (9999) open from internal RFC1918, following the existing
# default-deny per-service allow model. Egress: outbound-internal (Postgres,
# LiteLLM router) plus outbound HTTPS (Docker install/images, embedding-model
# download) — same shape as the vectordb (Qdrant) Docker-in-LXC guests.

locals {
  memory_ports = var.pipeline_constants.memory_ports

  hindsight_services_rules = [
    { proto = "tcp", dport = tostring(local.memory_ports.hindsight_api), source = local.internal_src, comment = "Hindsight API + MCP from internal" },
    { proto = "tcp", dport = tostring(local.memory_ports.hindsight_cp), source = local.internal_src, comment = "Hindsight Control Plane UI from internal" },
    # Hindsight serves /metrics unauthenticated on the same API port (no
    # separate metrics listener upstream) — an explicit, named rule for the
    # Prometheus scraper, alongside the broader internal rule above. Inert
    # (empty source) when var.prometheus_scraper_trusted_src is unset.
    { proto = "tcp", dport = tostring(local.memory_ports.hindsight_api), source = var.prometheus_scraper_trusted_src, comment = "Hindsight /metrics (API port) from the Prometheus scraper" },
  ]
}

resource "proxmox_virtual_environment_cluster_firewall_security_group" "hindsight_services" {
  name    = "memory-svc"
  comment = "Hindsight agent memory (${local.memory_ports.hindsight_api} API/MCP, ${local.memory_ports.hindsight_cp} CP UI) from internal networks"

  dynamic "rule" {
    for_each = local.hindsight_services_rules
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

resource "proxmox_virtual_environment_firewall_options" "hindsight_container" {
  for_each = var.hindsight_container_ids

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

resource "proxmox_virtual_environment_firewall_rules" "hindsight_container" {
  for_each = var.hindsight_container_ids

  node_name    = var.node_name
  container_id = each.value

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.internal_access.name
    comment        = "Internal access (SSH, ICMP)"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.hindsight_services.name
    comment        = "Hindsight (API/MCP, CP UI)"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.outbound_internal.name
    comment        = "Outbound to internal only"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.outbound_https.name
    comment        = "Outbound HTTPS (Docker install/images, embedding model)"
  }

  depends_on = [proxmox_virtual_environment_firewall_options.hindsight_container]
}
