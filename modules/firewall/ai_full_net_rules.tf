# =============================================================================
# AI runner container firewall configuration — `ai-full-net` egress profile
# =============================================================================
# Own file (like ai_runner_rules.tf / hermes_agent_rules.tf) so
# container_rules.tf stays under the shared _file-size workflow's 12 KB gate.
#
# An ai-full-net runner is a headless coding-agent guest that needs general
# outbound web access (arbitrary HTTPS destinations), not just the GitHub +
# model-API set the `ai-github` profile targets. At the Proxmox firewall
# (L3/L4, no SNI/hostname filtering) that is expressed as the same two openings
# as ai-github — this profile is deliberately still TIGHT on internal reach:
#
#   - internal_access  : SSH + ICMP in from internal RFC1918 — the Ansible
#                        controller converges the guest over SSH.
#   - ai_full_net_egress: outbound to internal INFRASTRUCTURE services ONLY —
#                        DNS (53), NTP (123, TLS clock validity), OpenBao API
#                        (8200, AppRole login + credential mint). Explicitly NO
#                        other internal/LAN dports: this guest cannot reach
#                        arbitrary internal hosts (no blanket RFC1918 egress).
#   - outbound_https   : TCP 443 to anywhere — the "full net" of this profile.
#                        443-to-any is the minimal L3/L4 opening for general web
#                        access (same reasoning as outbound_https_rules).
#
# True per-destination scoping (allowlist specific hosts) is NOT enforceable at
# the Proxmox firewall — it filters on IP/port, not hostname. That needs an
# egress forward-proxy (the same Squid hardening follow-up tracked for
# hermes_agent). Documented, not silently widened.

locals {
  # Outbound to internal infrastructure services only — the minimum a confined
  # guest needs to function, identical to the ai-github internal base. WAN
  # reach is the separately-attached outbound_https group, not this list.
  ai_full_net_egress_rules = [
    { proto = "udp", dport = "53", dest = local.internal_src, comment = "DNS (UDP 53) to internal resolvers" },
    { proto = "tcp", dport = "53", dest = local.internal_src, comment = "DNS (TCP 53) to internal resolvers" },
    { proto = "udp", dport = tostring(local.svc_ports.ntp), dest = local.internal_src, comment = "NTP (UDP ${local.svc_ports.ntp}) to internal — TLS clock validity" },
    { proto = "tcp", dport = tostring(local.svc_ports.openbao_api), dest = local.internal_src, comment = "OpenBao API (TCP ${local.svc_ports.openbao_api}) to internal — AppRole login + credential mint" },
  ]
}

resource "proxmox_virtual_environment_cluster_firewall_security_group" "ai_full_net_egress" {
  name    = "ai-full-net-egress"
  comment = "AI runner ai-full-net profile: outbound to internal DNS/NTP/OpenBao only (general WAN goes via outbound-https)"

  dynamic "rule" {
    for_each = local.ai_full_net_egress_rules
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

resource "proxmox_virtual_environment_firewall_options" "ai_full_net_container" {
  for_each = var.ai_full_net_container_ids

  node_name     = var.node_name
  container_id  = each.value
  enabled       = local.firewall_defaults.enabled
  input_policy  = local.firewall_defaults.input_policy
  output_policy = local.firewall_defaults.output_policy
  log_level_in  = local.firewall_defaults.log_level_in
  log_level_out = local.firewall_defaults.log_level_out

  # DHCP-first guest (leases its reserved ai-VLAN address by MAC). Behind DROP
  # in/out it needs DHCPDISCOVER/OFFER allowed or it never leases — same reason
  # as ai_runner_rules.tf / ai_orchestration_rules.tf.
  dhcp = true

  depends_on = [proxmox_virtual_environment_cluster_firewall.main]
}

resource "proxmox_virtual_environment_firewall_rules" "ai_full_net_container" {
  for_each = var.ai_full_net_container_ids

  node_name    = var.node_name
  container_id = each.value

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.internal_access.name
    comment        = "Internal access (SSH, ICMP) — Ansible converge"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.ai_full_net_egress.name
    comment        = "Outbound to internal DNS/NTP/OpenBao only"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.outbound_https.name
    comment        = "Outbound HTTPS (TCP 443) to any — general web access"
  }

  depends_on = [proxmox_virtual_environment_firewall_options.ai_full_net_container]
}
