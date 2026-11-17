locals {
  # Hermes guests on the shared proxied egress profile: Pepper and every isolated roster identity.
  hermes_pepper_container_ids = {
    for k, v in var.containers : k => v.vm_id
    if length(setintersection(
      toset(coalesce(try(v.tags, null), [])),
      toset([local.firewall_container_tags.hermes_pepper, local.firewall_container_tags.hermes_isolated]),
    )) > 0
  }

  hermes_isolated_container_keys = sort([
    for k, v in var.containers : k
    if contains(coalesce(try(v.tags, null), []), local.firewall_container_tags.hermes_isolated)
  ])
}
