# wall tag-filter local — same split and shape as locals-glance.tf.

locals {
  # Server-room wall — static pages plus a read-only data gateway on wall_web.
  # modules/firewall opens the port from internal. Carries the shared
  # `dashboard` tag alongside its own.
  wall_container_ids = {
    for k, v in var.containers : k => v.vm_id
    if contains(coalesce(try(v.tags, null), []), "wall")
  }
}
