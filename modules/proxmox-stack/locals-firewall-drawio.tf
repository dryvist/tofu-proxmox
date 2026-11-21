locals {
  next_ai_drawio_ingress_src = join(",", local.ingress_hosts)
  # The firewall accepts addresses only; DHCP router guests advertise names, so use their VLAN networks.
  next_ai_drawio_mcp_src = join(",", sort(distinct([
    for k, v in var.containers : nonsensitive(var.network_cidrs[v.vlan])
    if contains(coalesce(try(v.tags, null), []), local.firewall_container_tags.llm_router)
  ])))
}
