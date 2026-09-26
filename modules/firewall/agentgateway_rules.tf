# =============================================================================
# agentgateway container firewall configuration
# =============================================================================
# agentgateway (github.com/agentgateway/agentgateway) is a Rust-written
# AI-first data plane that unifies MCP (Model Context Protocol), LLM traffic,
# and A2A (agent-to-agent) communication into a single proxy. It provides
# RBAC, JWT auth, mTLS, built-in OpenTelemetry, and an Envoy-compatible xDS
# control plane — acting as the security + observability boundary for the
# homelab's AI agent fabric.
#
# Port allocation (DRY from pipeline_constants.service_ports):
#   agentgateway_proxy (8080)  — MCP/LLM/A2A proxy/traffic port. AI agents,
#                                OpenAI-compatible callers, and MCP clients
#                                dial this port; agentgateway routes to backend
#                                MCP servers, llm-router, and llm-fast.
#   agentgateway_admin (15000)   — Admin UI / xDS config dump. Fronted by
#                                  Traefik at agentgateway.<domain>.
#                                  Internal-only.
#   agentgateway_metrics (15020) — Stats server (Prometheus /metrics);
#                                  scraped directly by Prometheus.
#                                  Internal-only.
#
# Firewall profile:
#   inbound  : internal_access (SSH + ICMP) + agentgateway_svc (8080 + 15000)
#   outbound : outbound_internal (local LLM fabric via llm-router, DNS, NTP)
#            + outbound_https   (external MCP servers, upstream LLM API
#                                providers, package installs)
#
# DHCP-first on the ai VLAN (same pattern as llm-router / llm-fast):
#   dhcp = true on the options resource is required because the container's
#   DROP input policy would otherwise block DHCPDISCOVER/OFFER, preventing
#   the container from acquiring its reserved ai-VLAN address.
#
# Extracted into its own file (same rationale as llm_fabric_rules.tf,
# hermes_agent_rules.tf) to keep container_rules.tf under the shared
# _file-size workflow's 12 KB error threshold.

locals {
  agentgateway_services_rules = [
    {
      proto   = "tcp"
      dport   = tostring(local.svc_ports.agentgateway_proxy)
      source  = local.internal_src
      comment = "agentgateway MCP/LLM/A2A proxy (TCP ${local.svc_ports.agentgateway_proxy}) from internal"
    },
    {
      proto   = "tcp"
      dport   = tostring(local.svc_ports.agentgateway_admin)
      source  = local.internal_src
      comment = "agentgateway admin UI + xDS (TCP ${local.svc_ports.agentgateway_admin}) from internal"
    },
    {
      proto   = "tcp"
      dport   = tostring(local.svc_ports.agentgateway_metrics)
      source  = local.internal_src
      comment = "agentgateway stats server Prometheus /metrics (TCP ${local.svc_ports.agentgateway_metrics}) from internal"
    },
    {
      # Explicit, named rule for the Prometheus scraper, alongside the
      # broader internal rule above. Inert (empty source) when
      # var.prometheus_scraper_trusted_src is unset.
      proto   = "tcp"
      dport   = tostring(local.svc_ports.agentgateway_metrics)
      source  = var.prometheus_scraper_trusted_src
      comment = "agentgateway stats server Prometheus /metrics (TCP ${local.svc_ports.agentgateway_metrics}) from the Prometheus scraper"
    },
  ]
}

resource "proxmox_virtual_environment_cluster_firewall_security_group" "agentgateway_services" {
  name    = "agentgateway-svc"
  comment = "agentgateway proxy (${local.svc_ports.agentgateway_proxy}) + admin (${local.svc_ports.agentgateway_admin}) from internal networks"

  dynamic "rule" {
    for_each = local.agentgateway_services_rules
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

resource "proxmox_virtual_environment_firewall_options" "agentgateway_container" {
  for_each = var.agentgateway_container_ids

  node_name     = var.node_name
  container_id  = each.value
  enabled       = local.firewall_defaults.enabled
  input_policy  = local.firewall_defaults.input_policy
  output_policy = local.firewall_defaults.output_policy
  log_level_in  = local.firewall_defaults.log_level_in
  log_level_out = local.firewall_defaults.log_level_out

  # DHCP-first on the ai VLAN: DROP input policy blocks DHCPDISCOVER without
  # this flag — the container would never acquire its reserved address.
  dhcp = true

  depends_on = [proxmox_virtual_environment_cluster_firewall.main]
}

resource "proxmox_virtual_environment_firewall_rules" "agentgateway_container" {
  for_each = var.agentgateway_container_ids

  node_name    = var.node_name
  container_id = each.value

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.internal_access.name
    comment        = "Internal access (SSH, ICMP)"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.agentgateway_services.name
    comment        = "agentgateway MCP/LLM/A2A proxy + admin UI from internal"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.outbound_internal.name
    comment        = "Outbound to internal (local LLM fabric via llm-router, DNS, NTP)"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.outbound_https.name
    comment        = "Outbound HTTPS (external MCP servers, upstream LLM API providers, package installs)"
  }

  depends_on = [proxmox_virtual_environment_firewall_options.agentgateway_container]
}
