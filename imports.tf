# Adoption of guests that exist in Proxmox but not in tofu state.
#
# TRANSIENT. Delete this file in a follow-up PR once the adopting apply has run;
# an import block for an already-managed resource is a no-op, so leaving it here
# is harmless but misleading — it reads as "these are still unmanaged" forever.
#
# WHY AN IMPORT AND NOT A DATA EDIT. `vikunja` (605010) is live but absent from
# state. Refresh looks a guest up by the node recorded in STATE, so with no
# state entry it plans a CREATE. Proxmox VMIDs are cluster-unique, so that
# create can never succeed against the live guest: the apply hangs waiting for
# the container configuration to unlock and then errors, and everything
# downstream of the containers (notably aws_s3_object.ansible_inventory, whose
# content iterates container_details) is skipped along with it.
#
# Correcting node_name in the deployment object alone does NOT fix this — that
# is measured, not assumed: with node_name set to the real node the plan still
# reported a create, because config cannot retroactively change what refresh
# already looked for. The edit is still a prerequisite, because node_name is
# ForceNew in the pinned bpg/proxmox v0.111.1: importing while the declared
# node disagreed with reality would plan destroy+recreate of a running guest
# rather than an adoption. The deployment object now declares the node the
# guest actually runs on, so the import adopts in place.
#
# The ids are derived from the deployment object rather than written out, so no
# real node name is committed here and the block cannot drift from the declared
# placement it is adopting. Format is `node/vmid`, per parseImportIDWithNodeName
# in the pinned provider.
#
# This guest is HA-managed, so Proxmox may relocate it and reopen the same
# divergence. Verify the declared node still matches reality immediately before
# the adopting apply.
locals {
  # Guests that exist in Proxmox but are absent from tofu state. Empty is the
  # steady state; a name here is a claim that the guest is live and unmanaged.
  adopt_containers = ["vikunja"]
}

import {
  for_each = toset(local.adopt_containers)

  to = module.homelab.module.containers[0].proxmox_virtual_environment_container.containers[each.value]
  id = "${local.deployment.containers[each.value].node_name}/${local.deployment.containers[each.value].vm_id}"
}
