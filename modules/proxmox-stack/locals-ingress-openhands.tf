# Traefik routes for the OpenHands VM, split out of locals-ingress-backends.tf
# so that file stays under the shared _file-size 12 KB error threshold. Locals
# merge across files in the module, same treatment as locals-ingress-iac.tf.
locals {
  # OpenHands on the sandbox VM that also carries the "openhands" tag (DHCP/
  # DNS-first, ai VLAN). Appended like the ZCode route, but conditionally on
  # exactly one such VM — a deployment without one never emits dangling routes.
  # The backend is local.vm_address: the VM's FQDN, never an IP (DNS-first
  # doctrine). Two routes: the browser UI (SSO-gated) and the automation-events
  # webhook receiver, which verifies its own HMAC signature and therefore
  # bypasses the Authelia gate — one narrow path, never a whole-host row (see
  # locals-ingress-ai-routes.tf).
  openhands_routes = length(local.openhands_vm_ids) == 1 ? [
    {
      name   = "openhands"
      owner  = keys(local.openhands_vm_ids)[0]
      ip     = local.vm_address[keys(local.openhands_vm_ids)[0]]
      port   = local.pipeline_constants.service_ports.openhands_web
      scheme = "http"
      sso    = true
    },
    {
      name        = "openhands-events"
      hostname    = "openhands"
      path_prefix = "/api/automation/v1/events/"
      priority    = 100
      owner       = keys(local.openhands_vm_ids)[0]
      ip          = local.vm_address[keys(local.openhands_vm_ids)[0]]
      port        = local.pipeline_constants.service_ports.openhands_web
      scheme      = "http"
      sso         = false
    }
  ] : []
}
