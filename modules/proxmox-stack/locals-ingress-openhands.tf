# Traefik routes for the OpenHands VM, in their own file so
# locals-ingress-backends.tf stays under the shared _file-size 12 KB error
# threshold (same split as locals-ingress-iac.tf). Locals merge across files
# in the module; the list is concatenated into local.ingress_base by
# locals-ingress-backends.tf.
#
# Their dashboard group is set in locals-ingress-groups.tf: these are VM-backed,
# so there is no backend container whose VLAN could be inherited.

locals {
  # OpenHands (the agent-sandbox VM that also carries the "openhands" tag,
  # DHCP/DNS-first). Appended like the Splunk VM (VMs are not in
  # var.containers, so no ingress_services row), but conditionally — a
  # deployment without exactly one openhands-tagged VM never emits dangling
  # routes. The backend is local.vm_address: the VM's FQDN, never an IP
  # (DNS-first doctrine).
  #
  # The browser UI stays SSO-gated. The automation-events webhook is the one
  # narrow machine path on the shared hostname without SSO (same shape as the
  # dify-api-v1 / langfuse-otlp rows — one narrow path, never a whole host):
  # the receiver verifies its HMAC signature itself, and source_ranges narrows
  # who can reach it to the vikunja container's VLAN (nonsensitive, same as
  # git-mirror's trusted ranges — var.network_cidrs is a sensitive variable).
  # Each route is its own one-element conditional: the two objects have
  # different attribute sets, so a single two-element tuple cannot share a type
  # with the empty false branch.
  openhands_routes = concat(
    length(local.openhands_vm_ids) == 1 ? [
      {
        name   = "openhands"
        owner  = keys(local.openhands_vm_ids)[0]
        ip     = local.vm_address[keys(local.openhands_vm_ids)[0]]
        port   = local.pipeline_constants.service_ports.openhands_web
        scheme = "http"
        sso    = true
      }
    ] : [],
    length(local.openhands_vm_ids) == 1 ? [
      {
        name          = "openhands-events"
        owner         = keys(local.openhands_vm_ids)[0]
        ip            = local.vm_address[keys(local.openhands_vm_ids)[0]]
        port          = local.pipeline_constants.service_ports.openhands_web
        scheme        = "http"
        hostname      = "openhands"
        path_prefix   = "/api/automation/v1/events/"
        priority      = 100
        sso           = false
        source_ranges = [nonsensitive(var.network_cidrs[var.containers["vikunja"].vlan])]
      }
    ] : [],
  )
}
