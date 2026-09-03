# status tag-filter local — Gatus + Uptime Kuma Docker-in-LXC guest.
# Split like locals-homepage.tf so locals.tf stays under the _file-size gate.

locals {
  # Status guest carries both synthetics UIs. modules/firewall opens gatus_web
  # and uptime_kuma_web from internal. Tag `status` selects the guest; Traefik
  # routes `gatus` / `uptime-kuma` both point at this backend hostname.
  status_container_ids = {
    for k, v in var.containers : k => v.vm_id
    if contains(coalesce(try(v.tags, null), []), "status")
  }
}
