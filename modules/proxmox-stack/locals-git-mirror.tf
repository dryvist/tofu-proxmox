# Git mirror placement, trusted-client source ranges, and proxy sources.
locals {
  git_mirror_trusted_source_ranges = nonsensitive(distinct([
    for vlan, cidr in var.network_cidrs : cidr
    if vlan != "ai" && cidr != var.network_cidrs["ai"]
  ]))

  git_mirror_ingress_src = join(",", compact(local.ingress_hosts))
  git_mirror_trusted_src = join(",", local.git_mirror_trusted_source_ranges)
}
