# Firecrawl page-extraction LXC firewall (firecrawl tag, ai VLAN). Its own
# file, not container_rules.tf, to keep that file under the shared _file-size
# workflow's 12 KB gate — same split as hindsight_rules.tf and postgres_rules.tf.
#
# INGRESS SCOPE, stated precisely because the service itself is unauthenticated
# (upstream self-host default is USE_DB_AUTHENTICATION=false, and the client
# key the agents send is a placeholder the service does not verify):
#
#   The API is open from the AI VLAN ONLY (ai_src), not from internal RFC1918.
#   That is deliberately narrower than the sibling Hindsight service, which
#   opens from all internal networks — this one has no auth of its own, so the
#   network is the entire control and it gets the tightest scope available.
#
#   What this does NOT do is restrict by container. These are DHCP-first guests
#   with no static addresses, so the Proxmox firewall has no per-guest source to
#   match on; anything else on the AI VLAN can reach the API. Narrowing further
#   means either static addressing for the agent guests or real auth on the
#   service. Do not describe this rule as "only the Hermes guests can reach it".
#
# Egress: outbound-internal (DNS, NTP, syslog) plus outbound HTTPS, which is
# load-bearing here rather than incidental — fetching arbitrary public pages IS
# this service's job, and it also pulls its own container images.

locals {
  extract_ports = var.pipeline_constants.extract_ports

  firecrawl_services_rules = [
    { proto = "tcp", dport = tostring(local.extract_ports.firecrawl_api), source = local.ai_src, comment = "Firecrawl API from the AI VLAN only (service is unauthenticated)" },
  ]
}

resource "proxmox_virtual_environment_cluster_firewall_security_group" "firecrawl_services" {
  name    = "extract-svc"
  comment = "Firecrawl page extraction (${local.extract_ports.firecrawl_api}) from the AI VLAN only"

  dynamic "rule" {
    for_each = local.firecrawl_services_rules
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

resource "proxmox_virtual_environment_firewall_options" "firecrawl_container" {
  for_each = var.firecrawl_container_ids

  node_name     = var.node_name
  container_id  = each.value
  enabled       = local.firewall_defaults.enabled
  input_policy  = local.firewall_defaults.input_policy
  output_policy = local.firewall_defaults.output_policy
  log_level_in  = local.firewall_defaults.log_level_in
  log_level_out = local.firewall_defaults.log_level_out

  # DHCP-first guest behind DROP policies (same reason as hindsight_rules.tf).
  dhcp = true

  depends_on = [proxmox_virtual_environment_cluster_firewall.main]
}

resource "proxmox_virtual_environment_firewall_rules" "firecrawl_container" {
  for_each = var.firecrawl_container_ids

  node_name    = var.node_name
  container_id = each.value

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.internal_access.name
    comment        = "Internal access (SSH, ICMP)"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.outbound_internal.name
    comment        = "Outbound to internal only (DNS, NTP, syslog)"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.outbound_https.name
    comment        = "Outbound HTTPS — fetching public pages is this service's function"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.firecrawl_services.name
    comment        = "Inbound extraction API from the AI VLAN"
  }

  depends_on = [proxmox_virtual_environment_firewall_options.firecrawl_container]
}
