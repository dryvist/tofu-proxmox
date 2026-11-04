# =============================================================================
# AI runner container firewall configuration — `ai-github` egress profile
# =============================================================================
# Own file (like hermes_agent_rules.tf / ai_orchestration_rules.tf) so
# container_rules.tf stays under the shared _file-size workflow's 12 KB gate.
#
# An AI runner is a headless guest that runs a coding agent (Claude Code / Codex)
# in permission-skipping mode. Safety is enforced entirely at this container
# boundary, so egress is the whole control. The `ai-github` profile is the
# tightest of the AI-plane profiles: default-deny out, with only the destinations
# a GitHub-oriented agent job needs.
#
#   - internal_access   : SSH + ICMP in from internal RFC1918 — the Ansible
#                         controller converges the guest over SSH.
#   - ai_github_egress  : outbound to internal INFRASTRUCTURE services only —
#                         DNS (53), NTP (123, TLS clock validity), OpenBao API
#                         (8200, AppRole login + credential mint). NOT blanket
#                         RFC1918: unlike hermes_agent this guest cannot reach
#                         arbitrary internal hosts.
#   - outbound_https    : TCP 443 to anywhere — github.com/api.github.com and the
#                         Anthropic/OpenAI APIs are all CDN-fronted with no stable
#                         dest CIDR, so 443-to-any is the minimal L3/L4 opening
#                         (same reasoning as outbound_https_rules for Cribl/hermes).
#
# FQDN allowlisting (github/anthropic/openai ONLY, vs any 443 host) is NOT
# enforceable at the Proxmox firewall — it filters on IP/port, not SNI/hostname.
# True per-destination scoping needs an egress forward-proxy (the same Squid
# hardening follow-up already tracked for hermes_agent). Documented, not silently
# widened.
#
# Dispatch-plane note: the runner's job queue is Vikunja and results push to ntfy,
# both internal app-VLAN services. Their ports are NOT in this egress group yet —
# they are an ansible-proxmox-ai (PR2) implementation detail. Add the specific
# Vikunja/ntfy dports here once PR2 finalizes them, OR the operator widens this
# guest to the outbound_internal group. Left as an explicit follow-up rather than
# pre-granting blanket internal egress.

locals {
  # Outbound to internal infrastructure services only — the minimum a confined
  # guest needs to function regardless of workload. Ports DRY from
  # pipeline_constants; DNS 53 is a well-known literal (no constant), same idiom
  # as the "22"/"443" literals elsewhere in this module.
  ai_github_egress_rules = [
    { proto = "udp", dport = "53", dest = local.internal_src, comment = "DNS (UDP 53) to internal resolvers" },
    { proto = "tcp", dport = "53", dest = local.internal_src, comment = "DNS (TCP 53) to internal resolvers" },
    { proto = "udp", dport = tostring(local.svc_ports.ntp), dest = local.internal_src, comment = "NTP (UDP ${local.svc_ports.ntp}) to internal — TLS clock validity" },
    { proto = "tcp", dport = tostring(local.svc_ports.openbao_api), dest = local.internal_src, comment = "OpenBao API (TCP ${local.svc_ports.openbao_api}) to internal — AppRole login + credential mint" },
  ]
}

resource "proxmox_virtual_environment_cluster_firewall_security_group" "ai_github_egress" {
  name    = "ai-github-egress"
  comment = "AI runner ai-github profile: outbound to internal DNS/NTP/OpenBao only (github + model APIs go via outbound-https)"

  dynamic "rule" {
    for_each = local.ai_github_egress_rules
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

resource "proxmox_virtual_environment_firewall_options" "ai_github_container" {
  for_each = var.ai_github_container_ids

  node_name     = var.node_name
  container_id  = each.value
  enabled       = local.firewall_defaults.enabled
  input_policy  = local.firewall_defaults.input_policy
  output_policy = local.firewall_defaults.output_policy
  log_level_in  = local.firewall_defaults.log_level_in
  log_level_out = local.firewall_defaults.log_level_out

  # DHCP-first guest (leases its reserved ai-VLAN address by MAC). Behind DROP
  # in/out it needs DHCPDISCOVER/OFFER allowed or it never leases — same reason
  # as hermes_agent_rules.tf / ai_orchestration_rules.tf.
  dhcp = true

  depends_on = [proxmox_virtual_environment_cluster_firewall.main]
}

resource "proxmox_virtual_environment_firewall_rules" "ai_github_container" {
  for_each = var.ai_github_container_ids

  node_name    = var.node_name
  container_id = each.value

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.internal_access.name
    comment        = "Internal access (SSH, ICMP) — Ansible converge"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.ai_github_egress.name
    comment        = "Outbound to internal DNS/NTP/OpenBao only"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.outbound_https.name
    comment        = "Outbound HTTPS (TCP 443) — github.com/api.github.com + Anthropic/OpenAI APIs (CDN-fronted)"
  }

  depends_on = [proxmox_virtual_environment_firewall_options.ai_github_container]
}
