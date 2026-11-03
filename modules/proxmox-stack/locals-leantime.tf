# Leantime tag-filter local — same split as locals-vikunja.tf. Consumed by the
# firewall module call in firewall.tf.

locals {
  # Leantime LXC (leantime tag) — native PHP install, web on leantime_web (80).
  # modules/firewall opens 80 to it from internal.
  leantime_container_ids = {
    for k, v in var.containers : k => v.vm_id
    if contains(coalesce(try(v.tags, null), []), local.firewall_container_tags.leantime)
  }
}
