# Local LLM fabric firewall resources. The GPU fast/small-model server (llm-fast)
# and the LiteLLM router (llm-router) live on the ai VLAN behind DROP in/out
# policies, so each gets `dhcp = true` (same reason as ai_orchestration_rules.tf).
#
# Rule data lives here (not in locals.tf) so that file stays under the shared
# _file-size 12 KB error threshold. local.svc_ports / local.internal_src are
# defined in locals.tf — cross-file local refs resolve within the module.
locals {
  # llm-router — the LiteLLM proxy fronting the fabric. Inbound llm_router_api
  # from internal so callers reach the OpenAI-compatible router endpoint.
  llm_router_services_rules = [
    { proto = "tcp", dport = tostring(local.svc_ports.llm_router_api), source = local.internal_src, comment = "LLM router / LiteLLM proxy (TCP ${local.svc_ports.llm_router_api}) from internal" },
  ]

  # llm-fast — the llama-swap GPU server. Inbound llm_fast_api from internal
  # (the router and direct callers reach the OpenAI-compatible fast endpoint).
  llm_fast_services_rules = [
    { proto = "tcp", dport = tostring(local.svc_ports.llm_fast_api), source = local.internal_src, comment = "LLM fast / llama-swap server (TCP ${local.svc_ports.llm_fast_api}) from internal" },
  ]
}

# Security groups (kept here, not security_groups.tf, to stay under its size gate)

resource "proxmox_virtual_environment_cluster_firewall_security_group" "llm_router_services" {
  name    = "llm-router-svc"
  comment = "LLM router / LiteLLM proxy API (${local.svc_ports.llm_router_api}) from internal networks"

  dynamic "rule" {
    for_each = local.llm_router_services_rules
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

resource "proxmox_virtual_environment_cluster_firewall_security_group" "llm_fast_services" {
  name    = "llm-fast-svc"
  comment = "LLM fast / llama-swap server API (${local.svc_ports.llm_fast_api}) from internal networks"

  dynamic "rule" {
    for_each = local.llm_fast_services_rules
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

# llm-router containers (LiteLLM proxy)

resource "proxmox_virtual_environment_firewall_options" "llm_router_container" {
  for_each = var.llm_router_container_ids

  node_name     = var.node_name
  container_id  = each.value
  enabled       = local.firewall_defaults.enabled
  input_policy  = local.firewall_defaults.input_policy
  output_policy = local.firewall_defaults.output_policy
  log_level_in  = local.firewall_defaults.log_level_in
  log_level_out = local.firewall_defaults.log_level_out

  # DHCP-first guests behind DROP policies need their own DHCPDISCOVER/OFFER
  # allowed or they never lease their reserved ai-VLAN address.
  dhcp = true

  depends_on = [proxmox_virtual_environment_cluster_firewall.main]
}

resource "proxmox_virtual_environment_firewall_rules" "llm_router_container" {
  for_each = var.llm_router_container_ids

  node_name    = var.node_name
  container_id = each.value

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.internal_access.name
    comment        = "Internal access (SSH, ICMP)"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.llm_router_services.name
    comment        = "LLM router / LiteLLM proxy API from internal"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.outbound_internal.name
    comment        = "Outbound to internal (llm-fast + off-box model endpoints, DNS)"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.outbound_https.name
    comment        = "Outbound HTTPS (external model APIs, package installs)"
  }

  # --- zero-trust (staged disabled): router is a fan-in for every consumer VLAN.
  dynamic "rule" {
    for_each = local.zt_src
    content {
      enabled = local.zt_enabled
      type    = "in"
      action  = "ACCEPT"
      proto   = "tcp"
      dport   = tostring(local.svc_ports.llm_router_api)
      source  = rule.value
      comment = "ZT: LLM router from ${rule.key}"
    }
  }

  depends_on = [proxmox_virtual_environment_firewall_options.llm_router_container]
}

# llm-fast containers (GPU llama-swap server)

resource "proxmox_virtual_environment_firewall_options" "llm_fast_container" {
  for_each = var.llm_fast_container_ids

  node_name     = var.node_name
  container_id  = each.value
  enabled       = local.firewall_defaults.enabled
  input_policy  = local.firewall_defaults.input_policy
  output_policy = local.firewall_defaults.output_policy
  log_level_in  = local.firewall_defaults.log_level_in
  log_level_out = local.firewall_defaults.log_level_out

  dhcp = true

  depends_on = [proxmox_virtual_environment_cluster_firewall.main]
}

resource "proxmox_virtual_environment_firewall_rules" "llm_fast_container" {
  for_each = var.llm_fast_container_ids

  node_name    = var.node_name
  container_id = each.value

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.internal_access.name
    comment        = "Internal access (SSH, ICMP)"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.llm_fast_services.name
    comment        = "LLM fast / llama-swap server API from internal"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.outbound_internal.name
    comment        = "Outbound to internal (DNS, model/weight fetch via internal mirror)"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.outbound_https.name
    comment        = "Outbound HTTPS (model/weight downloads, package installs)"
  }

  # --- zero-trust (staged disabled): intra-fabric only, not a fan-in like the router.
  rule {
    enabled = local.zt_enabled
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = tostring(local.svc_ports.llm_fast_api)
    source  = local.zt_src["ai"]
    comment = "ZT: llm-fast intra-ai"
  }

  depends_on = [proxmox_virtual_environment_firewall_options.llm_fast_container]
}

# llm-redis — the shared store the LiteLLM router pool counts spend in.
#
# Scoped to the AI VLAN, NOT internal_src like its neighbours above. Those serve
# callers across the estate; this one has exactly one client population, the
# router guests, which all sit on the ai VLAN. The routers are DHCP-first
# guests, so their individual addresses are not usable as a firewall source and
# the VLAN CIDR is the tightest scope this layer can express — still a real
# narrowing over "every internal network".
#
# The narrowing matters more here than for an API port. An unauthenticated Redis
# is a remote-code-execution primitive (CONFIG SET dir + SAVE), and while the
# role sets requirepass and renames CONFIG away, that is defence in depth rather
# than a reason to widen the reachable set.
locals {
  llm_redis_services_rules = [
    { proto = "tcp", dport = tostring(local.svc_ports.redis_default), source = var.ai_network, comment = "LLM router spend store (TCP ${local.svc_ports.redis_default}) from the ai VLAN only" },
  ]
}

resource "proxmox_virtual_environment_cluster_firewall_security_group" "llm_redis_services" {
  name    = "llm-redis-svc"
  comment = "LLM router spend store (${local.svc_ports.redis_default}) from the ai VLAN"

  dynamic "rule" {
    for_each = local.llm_redis_services_rules
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

resource "proxmox_virtual_environment_firewall_options" "llm_redis_container" {
  for_each = var.llm_redis_container_ids

  node_name     = var.node_name
  container_id  = each.value
  enabled       = local.firewall_defaults.enabled
  input_policy  = local.firewall_defaults.input_policy
  output_policy = local.firewall_defaults.output_policy
  log_level_in  = local.firewall_defaults.log_level_in
  log_level_out = local.firewall_defaults.log_level_out

  dhcp = true

  depends_on = [proxmox_virtual_environment_cluster_firewall.main]
}

resource "proxmox_virtual_environment_firewall_rules" "llm_redis_container" {
  for_each = var.llm_redis_container_ids

  node_name    = var.node_name
  container_id = each.value

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.internal_access.name
    comment        = "Internal access (SSH, ICMP)"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.llm_redis_services.name
    comment        = "Spend store from the ai VLAN"
  }

  # Outbound INTERNAL only, and deliberately no outbound_https. This guest
  # serves one port to one VLAN and originates nothing toward the internet; apt
  # reaches the internal cacher over the same internal egress. Omitting the WAN
  # rule keeps a data store off the list of things that can call out.
  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.outbound_internal.name
    comment        = "Outbound to internal (DNS, NTP, apt cacher)"
  }

  depends_on = [proxmox_virtual_environment_firewall_options.llm_redis_container]
}
