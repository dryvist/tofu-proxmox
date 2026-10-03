# AI sandbox VM (agent-sandbox tag): the Docker host that runs untrusted agent
# CLIs in ephemeral containers. See modules/firewall/ai_sandbox_rules.tf.
locals {
  ai_sandbox_vm_ids = {
    for k, v in var.vms : k => v.vm_id
    if contains(try(v.tags, []), "agent-sandbox")
  }

  # The only callers of the VM's HTTPS port — the ingress Traefik instances,
  # derived from the inventory, never literals.
  ai_sandbox_ingress_src = join(",", compact(local.ingress_hosts))
}
