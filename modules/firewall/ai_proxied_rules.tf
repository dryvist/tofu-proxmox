# =============================================================================
# AI agent-pool container firewall configuration — `ai-proxied` egress profile
# =============================================================================
# Own file (like ai_runner_rules.tf / ai_full_net_rules.tf) so
# container_rules.tf stays under the shared _file-size workflow's 12 KB gate.
#
# This is the profile for the long-lived AI agent POOL: N identical guests that
# pull work from a queue rather than being provisioned per run. It is strictly
# tighter than `ai-full-net` — the difference is the whole point of the profile:
#
#   - internal_access  : SSH + ICMP in from internal RFC1918 — the Ansible
#                        controller converges the guest over SSH.
#   - ai_proxied_egress: outbound to internal services ONLY —
#                        DNS (53), NTP (123, TLS clock validity), OpenBao API
#                        (8200, AppRole login + credential mint), the Squid
#                        forward proxy (squid_proxy), and the AI log-ingest
#                        TCP-JSON frontends (ai_log_ports) so the agent's own
#                        transcript/telemetry reaches Cribl -> Splunk.
#   - NO outbound_https: deliberately absent. `ai-github` and `ai-full-net`
#                        both attach 443-to-any because they have no proxy; an
#                        ai-proxied guest's only WAN path is CONNECT through
#                        Squid, which is where the DOMAIN allowlist lives.
#
# Per-agent-CLI variants (claude / codex / agy) are NOT separate profiles here.
# At L3/L4 they would be byte-identical rule sets — the only thing that differs
# between them is which hostnames they may reach, and hostname filtering is not
# expressible in the Proxmox firewall. That distinction belongs in the Squid
# ACLs (one ACL group per profile, keyed off the client address), not in a
# duplicated security group. One profile here, N allowlists there.

locals {
  # Egress destinations for a pooled agent. Every entry is internal — the guest
  # has no direct WAN rule at all.
  ai_proxied_egress_rules = concat([
    { proto = "udp", dport = "53", dest = local.internal_src, comment = "DNS (UDP 53) to internal resolvers" },
    { proto = "tcp", dport = "53", dest = local.internal_src, comment = "DNS (TCP 53) to internal resolvers" },
    { proto = "udp", dport = tostring(local.svc_ports.ntp), dest = local.internal_src, comment = "NTP (UDP ${local.svc_ports.ntp}) to internal — TLS clock validity" },
    { proto = "tcp", dport = tostring(local.svc_ports.openbao_api), dest = local.internal_src, comment = "OpenBao API (TCP ${local.svc_ports.openbao_api}) to internal — AppRole login + credential mint" },
    { proto = "tcp", dport = tostring(local.svc_ports.squid_proxy), dest = local.internal_src, comment = "Squid forward proxy (TCP ${local.svc_ports.squid_proxy}) — the ONLY WAN path; domain allowlist enforced there" },
    ],
    # Agent transcript/telemetry to the HAProxy-fronted Cribl TCP-JSON
    # receivers. Derived from ai_log_ports so a new source family expands this
    # automatically — no per-index port invented here.
    [for name, port in local.ai_log_ports : {
      proto   = "tcp"
      dport   = tostring(port)
      dest    = local.internal_src
      comment = "AI log ingest ${name} (TCP ${port}) to internal Cribl frontends"
    }]
  )
}

resource "proxmox_virtual_environment_cluster_firewall_security_group" "ai_proxied_egress" {
  name    = "ai-proxied-egress"
  comment = "AI agent pool ai-proxied profile: internal DNS/NTP/OpenBao + Squid proxy + Cribl log ingest only — no direct WAN"

  dynamic "rule" {
    for_each = local.ai_proxied_egress_rules
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

resource "proxmox_virtual_environment_firewall_options" "ai_proxied_container" {
  for_each = var.ai_proxied_container_ids

  node_name     = var.node_name
  container_id  = each.value
  enabled       = local.firewall_defaults.enabled
  input_policy  = local.firewall_defaults.input_policy
  output_policy = local.firewall_defaults.output_policy
  log_level_in  = local.firewall_defaults.log_level_in
  log_level_out = local.firewall_defaults.log_level_out

  # DHCP-first guest (leases its reserved ai-VLAN address by MAC). Behind DROP
  # in/out it needs DHCPDISCOVER/OFFER allowed or it never leases — same reason
  # as ai_runner_rules.tf / ai_full_net_rules.tf.
  dhcp = true

  depends_on = [proxmox_virtual_environment_cluster_firewall.main]
}

resource "proxmox_virtual_environment_firewall_rules" "ai_proxied_container" {
  for_each = var.ai_proxied_container_ids

  node_name    = var.node_name
  container_id = each.value

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.internal_access.name
    comment        = "Internal access (SSH, ICMP) — Ansible converge"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.ai_proxied_egress.name
    comment        = "Internal DNS/NTP/OpenBao + Squid proxy + Cribl log ingest — no direct WAN"
  }

  depends_on = [proxmox_virtual_environment_firewall_options.ai_proxied_container]
}
