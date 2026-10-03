# =============================================================================
# AI sandbox VM firewall configuration (`agent-sandbox` tag)
# =============================================================================
# The Docker host that runs untrusted agent CLIs in ephemeral containers. The
# VM itself is the egress point for the on-host allowlisting proxy, so it holds
# the same WAN reach as the squid LXC (80/443 to any); the per-domain allowlist
# is enforced by that proxy and a host-level filter drops any container packet
# that does not go to the proxy or DNS. The Proxmox firewall filters IP/port
# only, so it cannot express the domain list.
#
#   - internal_access   : SSH + ICMP in from internal — Ansible converge and
#                         operator login.
#   - ai_proxied_egress : internal DNS/NTP/OpenBao + Cribl AI log ingest
#                         (reused, as the squid LXC does).
#   - outbound_https/http: 443 and 80 to any — the on-host proxy and the
#                         image pulls.
#   - ai_sandbox_ingress: HTTPS from the ingress Traefik instances only, for
#                         interactive agent sessions.

locals {
  # Omitted (not emptied) without an ingress address: a sourceless rule would
  # accept the port from anywhere.
  ai_sandbox_ingress_rules = var.ai_sandbox_ingress_src == "" ? [] : [
    { proto = "tcp", dport = "443", source = var.ai_sandbox_ingress_src, comment = "HTTPS (TCP 443) from the ingress Traefik instances" },
  ]
}

resource "proxmox_virtual_environment_cluster_firewall_security_group" "ai_sandbox_ingress" {
  name    = "ai-sandbox-ingress"
  comment = "agent-sandbox VM: HTTPS inbound from the ingress Traefik instances only"

  dynamic "rule" {
    for_each = local.ai_sandbox_ingress_rules
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

resource "proxmox_virtual_environment_firewall_options" "ai_sandbox_vm" {
  for_each = var.ai_sandbox_vm_ids

  node_name     = var.node_name
  vm_id         = each.value
  enabled       = local.firewall_defaults.enabled
  input_policy  = local.firewall_defaults.input_policy
  output_policy = local.firewall_defaults.output_policy
  log_level_in  = local.firewall_defaults.log_level_in
  log_level_out = local.firewall_defaults.log_level_out

  # DHCP-first guest: behind DROP in/out it needs DHCPDISCOVER/OFFER allowed
  # or it never leases — same reason as the ai-VLAN container profiles.
  dhcp = true

  depends_on = [proxmox_virtual_environment_cluster_firewall.main]
}

resource "proxmox_virtual_environment_firewall_rules" "ai_sandbox_vm" {
  for_each = var.ai_sandbox_vm_ids

  node_name = var.node_name
  vm_id     = each.value

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.internal_access.name
    comment        = "Internal access (SSH, ICMP) — Ansible converge"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.ai_proxied_egress.name
    comment        = "Internal DNS/NTP/OpenBao + Cribl log ingest"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.outbound_https.name
    comment        = "Outbound HTTPS (TCP 443) to any — narrowed by the on-host allowlist proxy"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.outbound_http.name
    comment        = "Outbound HTTP (TCP 80) to any — narrowed by the on-host allowlist proxy"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.ai_sandbox_ingress.name
    comment        = "HTTPS inbound from the ingress Traefik instances"
  }

  depends_on = [proxmox_virtual_environment_firewall_options.ai_sandbox_vm]
}
