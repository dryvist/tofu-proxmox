# Firecrawl LXC (firecrawl tag): the self-hosted page-extraction service the
# Hermes agents call for web_extract. Its own tag and its own firewall map,
# because its ingress is deliberately narrower than anything else on the AI
# VLAN — only the agent guests may reach it. Split out of locals.tf so that
# file stays under the shared _file-size 12 KB gate, the same reason
# locals-hermes-ui.tf and locals-llm-fabric.tf were split out.
#
# Note the tag pair this works with: the SERVER guest carries "firecrawl",
# while the agent guests carry "firecrawl-client". They must stay distinct —
# a client tagged "firecrawl" would land in the map below and be treated as a
# service instance, which is exactly backwards.
locals {
  firecrawl_container_ids = {
    for k, v in var.containers : k => v.vm_id
    if contains(coalesce(try(v.tags, null), []), "firecrawl")
  }
}
