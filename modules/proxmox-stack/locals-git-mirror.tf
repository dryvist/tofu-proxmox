# Git mirror placement, trusted-client source ranges, and proxy sources.
locals {
  git_mirror_trusted_source_ranges = nonsensitive(distinct([
    for vlan, cidr in var.network_cidrs : cidr
    if vlan != "ai" && cidr != var.network_cidrs["ai"]
  ]))

  git_mirror_routes = {
    "git-mirror-public" = { hostname = "git-mirror", path_prefix = "/public", priority = 100, backend = "git-mirror", port = local.pipeline_constants.service_ports.git_mirror_public, sso = false }
    "git-mirror-all"    = { hostname = "git-mirror-all", path_prefix = "/all", priority = 100, backend = "git-mirror", port = local.pipeline_constants.service_ports.git_mirror_all, sso = false, source_ranges = local.git_mirror_trusted_source_ranges }
  }

  git_mirror_ingress_src = join(",", compact(local.ingress_hosts))
  git_mirror_trusted_src = join(",", local.git_mirror_trusted_source_ranges)
}
