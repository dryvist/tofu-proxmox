# Zammad tag-filter local — extracted from locals.tf so that file stays under
# the shared _file-size workflow's 12 KB limit (locals merge across files in a
# module, so this is a pure relocation with no behavior change). Consumed by the
# firewall module call in main.tf. Same split as locals-vikunja.tf.

locals {
  # Zammad LXC (zammad tag) — native ITSM/ticketing app (Rails + colocated
  # Elasticsearch + Redis), web/API on zammad_web (8080) behind nginx, state in
  # the shared Postgres. modules/firewall opens 8080 to it from internal.
  zammad_container_ids = {
    for k, v in var.containers : k => v.vm_id
    if contains(coalesce(try(v.tags, null), []), local.firewall_container_tags.zammad)
  }
}
