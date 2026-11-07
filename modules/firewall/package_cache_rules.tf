locals {
  apt_cacher_ng_services_rules = [
    { proto = "tcp", dport = tostring(local.svc_ports.apt_cacher_ng), source = local.internal_src, comment = "apt-cacher-ng from internal" },
    { proto = "tcp", dport = tostring(local.svc_ports.pypi_cache), source = local.internal_src, comment = "PyPI cache from internal" },
    { proto = "tcp", dport = tostring(local.svc_ports.npm_cache), source = local.internal_src, comment = "npm cache from internal" },
    { proto = "tcp", dport = tostring(local.svc_ports.raw_cache), source = local.internal_src, comment = "Raw HTTP cache from internal" },
  ]

  package_cache_egress_rules = length(var.package_cache_destinations) == 0 ? [] : [
    { proto = "tcp", dport = tostring(local.svc_ports.pypi_cache), dest = join(",", var.package_cache_destinations), comment = "PyPI cache guest" },
    { proto = "tcp", dport = tostring(local.svc_ports.npm_cache), dest = join(",", var.package_cache_destinations), comment = "npm cache guest" },
    { proto = "tcp", dport = tostring(local.svc_ports.raw_cache), dest = join(",", var.package_cache_destinations), comment = "Raw HTTP cache guest" },
  ]
}

resource "proxmox_virtual_environment_cluster_firewall_security_group" "package_cache_egress" {
  for_each = length(var.hermes_pepper_container_ids) > 0 ? { active = true } : {}

  name    = "package-cache-egress"
  comment = "Package cache listeners on internal networks"

  dynamic "rule" {
    for_each = local.package_cache_egress_rules
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
