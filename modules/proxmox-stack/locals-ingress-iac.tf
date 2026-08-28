# Traefik routes for the IaC automation platform VM, split out of
# locals-ingress-backends.tf so that file stays under the shared _file-size
# 12 KB error threshold. Locals merge across files in the module, so this is a
# pure relocation: the list is concatenated into local.ingress exactly as before.
#
# Their dashboard group is set in locals-ingress-groups.tf: these are VM-backed,
# so there is no backend container whose VLAN could be inherited.

locals {
  # IaC automation platform (Terrakube + Semaphore UI) on the iac-platform VM
  # (DHCP/DNS-first, mgmt VLAN). Appended like the Splunk VM (VMs are not
  # in var.containers, so no ingress_services row), but conditionally — a
  # deployment.json without the VM never emits dangling routes. The backend is
  # local.vm_address: the VM's FQDN, never an IP (DNS-first doctrine). Four
  # Terrakube hostnames are required upstream (UI/API/registry/dex each get
  # their own vhost); the executor is deliberately not fronted. Its node
  # powers off nightly — consumers must treat these routes as daytime-available.
  iac_platform_routes = contains(keys(var.vms), "iac-platform") ? [
    for svc in [
      # UI hosts stay gated (sso omitted -> true); the API/registry/dex hosts
      # serve machine clients (CLI, dex OIDC redirects) and opt out.
      { name = "terrakube", port = local.pipeline_constants.iac_platform_ports.terrakube_ui },
      { name = "terrakube-api", port = local.pipeline_constants.iac_platform_ports.terrakube_api, sso = false },
      { name = "terrakube-registry", port = local.pipeline_constants.iac_platform_ports.terrakube_registry, sso = false },
      { name = "terrakube-dex", port = local.pipeline_constants.iac_platform_ports.terrakube_dex, sso = false },
      { name = "semaphore", port = local.pipeline_constants.iac_platform_ports.semaphore_web },
      ] : {
      name = svc.name
      ip   = local.vm_address["iac-platform"]
      port = svc.port
      sso  = try(svc.sso, true)
    }
  ] : []
}
