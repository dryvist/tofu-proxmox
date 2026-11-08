# AI sandbox VMs (agent-sandbox tag): the Docker hosts that run untrusted agent
# CLIs in ephemeral containers. See modules/firewall/ai_sandbox_rules.tf.
locals {
  ai_sandbox_vm_ids = {
    for k, v in var.vms : k => v.vm_id
    if contains(try(v.tags, []), "agent-sandbox")
  }

  # The subset of sandbox VMs that also carry the "openhands" tag: the OpenHands
  # host. Its routes are assembled in locals-ingress-openhands.tf.
  openhands_vm_ids = {
    for k, v in local.ai_sandbox_vm_ids : k => v
    if contains(try(var.vms[k].tags, []), "openhands")
  }

  # ZCode Web must stay on a sandbox VM of its own, so the route's owner is the
  # agent-sandbox VM that does NOT carry the "openhands" tag — adding an
  # OpenHands sandbox VM never moves (or drops) the zcode route.
  zcode_web_vm_ids = {
    for k, v in local.ai_sandbox_vm_ids : k => v
    if !contains(keys(local.openhands_vm_ids), k)
  }

  # The only callers of the VM's HTTPS port — the ingress Traefik instances,
  # derived from the inventory, never literals.
  ai_sandbox_ingress_src = join(",", compact(local.ingress_hosts))
}
