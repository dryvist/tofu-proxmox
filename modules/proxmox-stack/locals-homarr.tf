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

  # One SSO-gated route per Homarr guest, named by its container key, merged
  # into ingress_services (ingress.tf). Same tag-generated shape as
  # locals-hermes-routes.tf: a second instance in the desired state publishes
  # its route, DNS name and dashboard tile with no edit here. The route name is
  # also the instance name ansible-proxmox-apps keys that guest's OpenBao path
  # and OIDC client on, so it must stay the container key.
  #
  # SSO by default. An instance listed in ingress_human_unauthed_routes
  # (locals-ingress-audience.tf) opts out there, in the one place that decides
  # it, and this derives the flag rather than repeating the name.
  homarr_routes = {
    for k, _ in local.homarr_container_ids : k => {
      backend = k
      port    = local.pipeline_constants.service_ports.homarr_web
      sso     = !contains(local.ingress_human_unauthed_routes, k)
    }
  }
}
