# YouTrack tag-filter local — same split as locals-vikunja.tf. Consumed by the
# firewall module call in firewall.tf.

locals {
  # YouTrack LXC (youtrack tag) — web on youtrack_web (8080).
  # modules/firewall opens 8080 to it from internal.
  youtrack_container_ids = {
    for k, v in var.containers : k => v.vm_id
    if contains(coalesce(try(v.tags, null), []), local.firewall_container_tags.youtrack)
  }
}
