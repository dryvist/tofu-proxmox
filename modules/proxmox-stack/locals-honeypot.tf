# Honeypot tag-filter locals — extracted from locals.tf so that file stays under
# the shared _file-size workflow's 12 KB limit (locals merge across files in a
# module, so this is a pure relocation with no behavior change). Consumed by the
# firewall module call in main.tf.

locals {
  # Honeypot LXCs (honeypot tag): per-VLAN OpenCanary tripwires + the apprise-api
  # alert gateway. The notify gateway additionally carries the "notify" tag so the
  # firewall module can split it out (open egress + apprise port) from the
  # tripwires (decoy ports + internal-only egress). Kept distinct from
  # notification_container_ids (Mailpit/ntfy) so a guest is never double-claimed
  # by two firewall_options resources.
  honeypot_container_ids = {
    for k, v in var.containers : k => v.vm_id
    if contains(coalesce(try(v.tags, null), []), local.firewall_container_tags.honeypot)
  }
  honeypot_notify_container_ids = {
    for k, v in var.containers : k => v.vm_id
    if contains(coalesce(try(v.tags, null), []), local.firewall_container_tags.honeypot) && contains(coalesce(try(v.tags, null), []), local.firewall_container_tags.notify)
  }

  # T-Pot deep-sensor VM(s): tagged "tpot" (wide-net input, restricted egress).
  tpot_vm_ids = {
    for k, v in var.vms : k => v.vm_id
    if contains(try(v.tags, []), "tpot")
  }
}
