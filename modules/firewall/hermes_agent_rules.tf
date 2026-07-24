# =============================================================================
# Hermes Agent container firewall configuration
# =============================================================================
# Extracted into its own file (like monitoring_rules.tf / s3_rules.tf)
# so container_rules.tf stays under the shared _file-size workflow's 12 KB error
# threshold.
#
# The Hermes Agent (NousResearch) is an autonomous agent that runs arbitrary
# terminal + web tools. The LXC is its blast-radius boundary, so egress matters:
#   - internal_access  : SSH + ICMP in from internal RFC1918 (management).
#   - outbound_internal: reach the model endpoint (homelab Ollama on the AI VLAN),
#                        DNS, NTP, and Splunk logging — RFC1918 only.
#   - outbound_https   : TCP 443 to anywhere, for the agent's web/search/browser
#                        tools (Agy review: a 443/53/123-only egress is too tight
#                        for arbitrary tool-calling).
#   - hermes_webhook   : inbound webhook receiver (Traefik-fronted hermes.<domain>),
#                        from internal only — event-driven agent trigger.
#   - hermes_dashboard : authenticated interactive Dashboard (Traefik-fronted
#                        hermes.<domain>), from internal only.
#   - hermes_api       : inbound job-submission API (Traefik-fronted
#                        hermes-api.<domain>), from internal only — bearer-authed
#                        `api_server` platform (POST /v1/runs, /api/jobs).
#
# Hardening follow-up (not this PR): route egress through an audited Squid
# forward-proxy and replace outbound_internal with a microsegmented allowlist so
# the agent cannot reach arbitrary internal hosts. Tracked in the deployment plan.

# Inbound webhook ACCEPT for the `hermes gateway` webhook receiver
# (/webhooks/<name>, HMAC-signed) so other agents/systems can trigger the agent.
# Scoped to internal so only in-cluster callers reach it; port DRY from
# pipeline_constants (svc_ports = var.pipeline_constants.service_ports).
locals {
  hermes_webhook_services_rules = [
    { proto = "tcp", dport = tostring(local.svc_ports.hermes_webhook), source = local.internal_src, comment = "Hermes webhook receiver (TCP ${local.svc_ports.hermes_webhook}) from internal" },
    { proto = "tcp", dport = tostring(local.svc_ports.hermes_dashboard), source = local.internal_src, comment = "Hermes Dashboard (TCP ${local.svc_ports.hermes_dashboard}) from internal" },
    { proto = "tcp", dport = tostring(local.svc_ports.hermes_api), source = local.internal_src, comment = "Hermes job-submission API (TCP ${local.svc_ports.hermes_api}) from internal" },
  ]
}

resource "proxmox_virtual_environment_cluster_firewall_security_group" "hermes_webhook_services" {
  name    = "hermes-webhook-svc"
  comment = "Hermes agent services (dashboard ${local.svc_ports.hermes_dashboard}, webhook ${local.svc_ports.hermes_webhook}, job API ${local.svc_ports.hermes_api}) from internal networks — Traefik-fronted"

  dynamic "rule" {
    for_each = local.hermes_webhook_services_rules
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

resource "proxmox_virtual_environment_firewall_options" "hermes_agent_container" {
  for_each = var.hermes_agent_container_ids

  node_name     = var.node_name
  container_id  = each.value
  enabled       = local.firewall_defaults.enabled
  input_policy  = local.firewall_defaults.input_policy
  output_policy = local.firewall_defaults.output_policy
  log_level_in  = local.firewall_defaults.log_level_in
  log_level_out = local.firewall_defaults.log_level_out

  # hermes-agent is a DHCP-first guest (no static ip_config; leases its reserved
  # ai-VLAN address by MAC). Behind DROP in/out policies it needs its own
  # DHCPDISCOVER/OFFER allowed or it never leases — same reason as
  # ai_orchestration_rules.tf. (Previously supplied by the ai-orchestration tag;
  # required here now that hermes_agent is the sole manager of this ruleset.)
  dhcp = true

  depends_on = [proxmox_virtual_environment_cluster_firewall.main]
}

resource "proxmox_virtual_environment_firewall_rules" "hermes_agent_container" {
  for_each = var.hermes_agent_container_ids

  node_name    = var.node_name
  container_id = each.value

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.internal_access.name
    comment        = "Internal access (SSH, ICMP)"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.outbound_internal.name
    comment        = "Outbound to internal only (model endpoint, DNS, NTP, Splunk logging)"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.outbound_https.name
    comment        = "Outbound HTTPS (TCP 443) for agent web/search/browser tools"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.hermes_webhook_services.name
    comment        = "Inbound webhook receiver (Traefik-fronted) from internal"
  }

  depends_on = [proxmox_virtual_environment_firewall_options.hermes_agent_container]
}
