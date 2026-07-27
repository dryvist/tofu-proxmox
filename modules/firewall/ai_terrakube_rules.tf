# =============================================================================
# AI runner container firewall configuration — `ai-terrakube` egress profile
# =============================================================================
# Own file (like ai_runner_rules.tf / hermes_agent_rules.tf) so
# container_rules.tf stays under the shared _file-size workflow's 12 KB gate.
#
# An ai-terrakube runner is a headless guest that drives OpenTofu against the
# private Terrakube backend. Unlike the `ai-github` profile it has NO WAN
# egress at all — every destination it needs is an internal homelab service:
#
#   - internal_access    : SSH + ICMP in from internal RFC1918 — the Ansible
#                          controller converges the guest over SSH.
#   - ai_terrakube_egress: outbound to internal INFRASTRUCTURE + IaC-platform
#                          services only —
#                            DNS (53), NTP (123, TLS clock validity),
#                            OpenBao API (8200, AppRole login + credential mint),
#                            Terrakube API (28081, TF backend + REST API) and
#                            registry (28082, module/provider source at init),
#                            RustFS S3 (9000, remote state + inventory objects).
#
# The Terrakube EXECUTOR has no client-facing port by design (see
# constants.tf iac_platform_ports: "it must never be fronted — only the API
# reaches it, on the compose-internal network"), so there is no executor dport
# to open here — the runner reaches the API, and Terrakube dispatches to its
# own executor internally.
#
# No outbound_https / outbound_http group is attached: an ai-terrakube job has
# no legitimate internet destination. All model/API traffic belongs to the
# `ai-github` or `ai-full-net` profiles, not this one.

locals {
  # iac_platform_ports is not aliased in locals_rules.tf (that map holds the
  # service_ports subset); reference it here for the Terrakube control-plane
  # ports this profile needs. Same DRY intent as local.svc_ports.
  terrakube_ports = var.pipeline_constants.iac_platform_ports

  # Outbound to internal infrastructure + IaC platform only. Ports DRY from
  # pipeline_constants; DNS 53 is a well-known literal (no constant), same idiom
  # as the "22"/"443" literals elsewhere in this module.
  ai_terrakube_egress_rules = [
    { proto = "udp", dport = "53", dest = local.internal_src, comment = "DNS (UDP 53) to internal resolvers" },
    { proto = "tcp", dport = "53", dest = local.internal_src, comment = "DNS (TCP 53) to internal resolvers" },
    { proto = "udp", dport = tostring(local.svc_ports.ntp), dest = local.internal_src, comment = "NTP (UDP ${local.svc_ports.ntp}) to internal — TLS clock validity" },
    { proto = "tcp", dport = tostring(local.svc_ports.openbao_api), dest = local.internal_src, comment = "OpenBao API (TCP ${local.svc_ports.openbao_api}) to internal — AppRole login + credential mint" },
    { proto = "tcp", dport = tostring(local.terrakube_ports.terrakube_api), dest = local.internal_src, comment = "Terrakube API (TCP ${local.terrakube_ports.terrakube_api}) to internal — TF backend + REST API" },
    { proto = "tcp", dport = tostring(local.terrakube_ports.terrakube_registry), dest = local.internal_src, comment = "Terrakube registry (TCP ${local.terrakube_ports.terrakube_registry}) to internal — module/provider source at init" },
    { proto = "tcp", dport = tostring(local.svc_ports.object_storage_s3), dest = local.internal_src, comment = "RustFS S3 API (TCP ${local.svc_ports.object_storage_s3}) to internal — remote state + inventory objects" },
  ]
}

resource "proxmox_virtual_environment_cluster_firewall_security_group" "ai_terrakube_egress" {
  name    = "ai-tkube-egress" # Proxmox caps SG names at 18 chars
  comment = "AI runner ai-terrakube profile: outbound to internal DNS/NTP/OpenBao + Terrakube API/registry + RustFS S3 only (no WAN)"

  dynamic "rule" {
    for_each = local.ai_terrakube_egress_rules
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

resource "proxmox_virtual_environment_firewall_options" "ai_terrakube_container" {
  for_each = var.ai_terrakube_container_ids

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

resource "proxmox_virtual_environment_firewall_rules" "ai_terrakube_container" {
  for_each = var.ai_terrakube_container_ids

  node_name    = var.node_name
  container_id = each.value

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.internal_access.name
    comment        = "Internal access (SSH, ICMP) — Ansible converge"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.ai_terrakube_egress.name
    comment        = "Outbound to internal DNS/NTP/OpenBao + Terrakube API/registry + RustFS S3 only"
  }

  depends_on = [proxmox_virtual_environment_firewall_options.ai_terrakube_container]
}
