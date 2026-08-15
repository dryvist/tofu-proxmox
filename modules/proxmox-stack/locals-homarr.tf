# Homarr tag-filter local — kept out of locals.tf so that file stays under the
# shared _file-size workflow's 12 KB limit (locals merge across files in a
# module, so this is a pure relocation with no behavior change). Consumed by the
# firewall module call in firewall.tf. Same split as locals-vikunja.tf.

locals {
  # Homarr LXC (homarr tag) — dashboard, web UI on homarr_web (7575), sqlite on
  # its own rootfs. modules/firewall opens 7575 to it from internal.
  #
  # This guest is the pilot for the community-scripts install-layer boundary
  # (private docs ADR "Proxmox community-scripts — borrow the install step,
  # nothing above it"). The borrowed installer supplies only the app install;
  # this file, the firewall rules, the port constant and the ingress route are
  # all still ours, which is the point the pilot is measuring.
  homarr_container_ids = {
    for k, v in var.containers : k => v.vm_id
    if contains(coalesce(try(v.tags, null), []), "homarr")
  }
}
