# AI sandbox VM (agent-sandbox tag): the Docker host that runs untrusted agent
# CLIs in ephemeral containers. See modules/firewall/ai_sandbox_rules.tf.
locals {
  ai_sandbox_vm_ids = {
    for k, v in var.vms : k => v.vm_id
    if contains(try(v.tags, []), "agent-sandbox")
  }

  # The sandbox VM that additionally carries the "openhands" tag: the OpenHands
  # host. An extra tag on the same agent-sandbox VM, so it still gets the
  # sandbox firewall profile above — only the ingress route ownership differs.
  openhands_vm_ids = {
    for k, v in local.ai_sandbox_vm_ids : k => v
    if contains(try(var.vms[k].tags, []), "openhands")
  }

  # ZCode Web stays on a sandbox VM that is NOT the OpenHands host, so a second
  # agent-sandbox VM never displaces (or removes) the zcode route.
  zcode_web_vm_ids = {
    for k, v in local.ai_sandbox_vm_ids : k => v
    if !contains(keys(local.openhands_vm_ids), k)
  }

  # The only callers of the VM's HTTPS port — the ingress Traefik instances,
  # derived from the inventory, never literals.
  ai_sandbox_ingress_src = join(",", compact(local.ingress_hosts))
}
