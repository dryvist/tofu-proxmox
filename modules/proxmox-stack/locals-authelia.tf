# Authelia tag-filter local — same locals-split treatment as locals-vikunja.tf
# (locals merge across files in a module). Consumed by the firewall module call
# in main.tf.

locals {
  # Authelia LXC (authelia tag) — native SSO portal / Traefik forwardAuth
  # provider, portal + authz API on authelia_portal (9091), state in local
  # SQLite. modules/firewall opens 9091 to it from internal.
  authelia_container_ids = {
    for k, v in var.containers : k => v.vm_id
    if contains(coalesce(try(v.tags, null), []), local.firewall_container_tags.authelia)
  }
}
