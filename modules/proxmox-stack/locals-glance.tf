# glance tag-filter local — kept out of locals.tf so that file stays under the
# shared _file-size workflow's 12 KB limit (locals merge across files in a
# module, so this is a pure relocation). Same split as locals-homarr.tf, whose
# shape this copies deliberately: all three dashboards are wired identically.

locals {
  # Glance — dashboard, web UI on glance_web (8080), config
  # rendered to a persistent mount. modules/firewall opens the port from
  # internal. Carries the shared `dashboard` tag alongside its own so the
  # estate can address all boards as a set.
  glance_container_ids = {
    for k, v in var.containers : k => v.vm_id
    if contains(coalesce(try(v.tags, null), []), "glance")
  }
}
