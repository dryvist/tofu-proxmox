# Adoption of guests whose state entry points at a node they no longer run on.
#
# WHY THIS RECURS. These guests are HA-managed, so Proxmox relocates them
# whenever a node is lost. Refresh looks a guest up by the node recorded in
# STATE, so after a relocation it 404s, drops the resource, and plans a CREATE.
# Proxmox VMIDs are cluster-unique, so that create can never succeed against the
# live guest: the apply sits until "timeout while waiting for container <vmid>
# configuration to become unlocked", then fails. Everything downstream of the
# containers is skipped with it — notably aws_s3_object.ansible_inventory, whose
# content iterates container_details — so one relocated guest freezes the
# published inventory that the consumer repos read.
#
# ORDER MATTERS, and it is measured rather than assumed:
#   1. Correct node_name in the deployment object FIRST. node_name is ForceNew
#      in the pinned bpg/proxmox provider, so importing while the declared node
#      disagrees with reality plans destroy+recreate of a running guest instead
#      of an adoption.
#   2. Remove the stale state entry. An import block whose address is already
#      present in state is a SILENT no-op — the plan still reports a create.
#   3. Then apply, and the import adopts in place.
#
# The ids are derived from the deployment object rather than written out, so no
# real node name is committed here and the block cannot drift from the declared
# placement it is adopting. Format is `node/vmid`.
#
# Verify the declared node still matches reality immediately before an adopting
# apply — HA can relocate a guest again between the edit and the run.
locals {
  # Guests whose live node and state node have diverged. Empty is the steady
  # state; a name here is a claim that the guest is live and mis-tracked.
  adopt_containers = [
    "nautobot",
    "download-vpn",
    "hindsight-2",
    "langfuse",
    "llamaindex",
    "llm-router-2",
    "openbao-02",
    "openbao-20",
    "openbao-21",
    "plex",
    "postgres-ai-2",
    "postgres-apps",
    "qdrant",
    "radarr",
    "seerr",
    "sonarr",
    "sortarr",
    "technitium-dns-2",
  ]
}

import {
  for_each = toset(local.adopt_containers)

  to = module.homelab.module.containers[0].proxmox_virtual_environment_container.containers[each.value]

  # Resolved against the MERGED container map, not `deployment.containers`
  # alone: the OpenBao voters are synthesised from `openbao_cluster.placement`
  # and exist only in the merged map, so deriving from the raw deployment
  # object fails on exactly the guests a placement change relocates.
  #
  # node_name is OPTIONAL in the schema, and the stack defaults an unset value
  # to the primary node. Mirror that same coalesce here: taking the raw
  # attribute would yield an import id of `null/<vmid>` for any container
  # relying on the default, which fails to adopt with a confusing error.
  id = "${coalesce(try(local.containers[each.value].node_name, null), local.deployment.proxmox_node)}/${local.containers[each.value].vm_id}"
}
