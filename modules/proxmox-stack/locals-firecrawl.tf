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

  # The ingress route, defined here rather than inline in
  # locals-ingress-backends.tf: that file sits ~50 bytes under the shared
  # _file-size 12 KB error gate, so an inline block would fail CI. It carries a
  # bare `local.firecrawl_routes,` reference in the concat instead.
  #
  # Derived from the tag-keyed pool, not from a container name. The hostname
  # carries the node digit under the multi-instance naming law, so a name
  # literal would silently drop this route the moment the guest moved nodes —
  # locals-ingress-backends.tf filters out routes whose backend key is absent,
  # with no error. One instance today; the pool shape costs nothing and means a
  # second replica needs no code change.
  #
  # sso = false: the callers are agent runtimes, which cannot complete a
  # browser login.
  firecrawl_routes = length(local.firecrawl_backends) > 0 ? [
    {
      name              = "firecrawl"
      backends          = local.firecrawl_backends
      port              = local.pipeline_constants.extract_ports.firecrawl_api
      health_check      = true
      health_check_path = "/health"
      sso               = false
    },
  ] : []
}
