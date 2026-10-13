# Vikunja tag-filter local — extracted from locals.tf so that file stays under
# the shared _file-size workflow's 12 KB limit (locals merge across files in a
# module, so this is a pure relocation with no behavior change). Consumed by the
# firewall module call in main.tf.

locals {
  # Vikunja LXC (vikunja tag) — native task-management app, web/API on
  # vikunja_web (3456), state in the shared Postgres. modules/firewall opens
  # 3456 to it from internal.
  vikunja_container_ids = {
    for k, v in var.containers : k => v.vm_id
    if contains(coalesce(try(v.tags, null), []), local.firewall_container_tags.vikunja)
  }
}
