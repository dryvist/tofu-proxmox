# =============================================================================
# Squid egress forward-proxy container firewall configuration (`squid` tag)
# =============================================================================
# The audited egress chokepoint the confined AI agent plane reaches WAN through.
# This is the guest side of the long-standing Squid hardening follow-up noted in
# ai_runner_rules.tf / ai_full_net_rules.tf / hermes_agent_rules.tf: the Proxmox
# firewall filters on IP/port only, so per-DESTINATION (domain) scoping has to
# happen in a proxy. This file grants the proxy exactly two things:
#
#   - squid_proxy_services : inbound TCP squid_proxy from the ai VLAN only —
#                            not all of internal. Only agent-plane guests may
#                            use the proxy; nothing else on the estate can
#                            borrow it as an open relay.
#   - internal_access       : SSH + ICMP in from internal — Ansible converge.
#   - ai_proxied_egress     : internal DNS/NTP/OpenBao (its own resolution,
#                             clock, and credentials) — reused rather than
#                             duplicated; the proxy legitimately needs the same
#                             internal infra set as its clients.
#   - outbound_https/http   : 443 + 80 to any. This guest is the ONE place in
#                             the agent plane that holds general WAN reach, and
#                             the Squid domain allowlist is what makes that
#                             narrow in practice.

resource "proxmox_virtual_environment_cluster_firewall_security_group" "squid_proxy_services" {
  name    = "squid-proxy-svc"
  comment = "Squid forward proxy (TCP ${local.svc_ports.squid_proxy}) inbound from the ai VLAN only — agent-plane egress chokepoint"

  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = tostring(local.svc_ports.squid_proxy)
    source  = var.ai_network
    comment = "Squid proxy (TCP ${local.svc_ports.squid_proxy}) from the ai VLAN"
  }
}

resource "proxmox_virtual_environment_firewall_options" "squid_proxy_container" {
  for_each = var.squid_proxy_container_ids

  node_name     = var.node_name
  container_id  = each.value
  enabled       = local.firewall_defaults.enabled
  input_policy  = local.firewall_defaults.input_policy
  output_policy = local.firewall_defaults.output_policy
  log_level_in  = local.firewall_defaults.log_level_in
  log_level_out = local.firewall_defaults.log_level_out

  # DHCP-first guest (reserved ai-VLAN address by MAC), same as its clients.
  dhcp = true

  depends_on = [proxmox_virtual_environment_cluster_firewall.main]
}

resource "proxmox_virtual_environment_firewall_rules" "squid_proxy_container" {
  for_each = var.squid_proxy_container_ids

  node_name    = var.node_name
  container_id = each.value

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.internal_access.name
    comment        = "Internal access (SSH, ICMP) — Ansible converge"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.squid_proxy_services.name
    comment        = "Squid proxy inbound from the ai VLAN"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.ai_proxied_egress.name
    comment        = "Internal DNS/NTP/OpenBao — same internal infra set as its clients"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.outbound_https.name
    comment        = "Outbound HTTPS (TCP 443) to any — narrowed by the in-guest Squid domain allowlist"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.outbound_http.name
    comment        = "Outbound HTTP (TCP 80) to any — narrowed by the in-guest Squid domain allowlist"
  }

  depends_on = [proxmox_virtual_environment_firewall_options.squid_proxy_container]
}
