# A container's storage must exist on the node the container runs on.
#
# WHAT THIS CAUGHT. A guest declared its data mount on the `fast` pool while
# running on a node where `fast` is a cluster-wide storage ID owned by a
# DIFFERENT node — present in `pvesm status`, `disabled`, zero bytes. The apply
# succeeded and the volume was created on that node's default datastore
# instead. So the declaration said one thing, the guest ran on another, and
# nothing reconciled the two: `mount_point` is in the container resource's
# `lifecycle.ignore_changes` (mounts are effectively set-once), so no later plan
# re-reads the mount and no drift is ever reported. The discovery cost was a
# PostgreSQL primary that had been running on 7200 RPM spinning disks for weeks
# while its config claimed solid-state.
#
# The failure is silent by construction, which is what earns a hard guard: the
# usual signal for a wrong value — a plan that wants to change it — cannot fire
# for an attribute the plan is told to ignore.
#
# WHY THIS IS A STATIC CHECK, not a live query. The provider does expose a
# per-node datastore data source (`proxmox_datastores`, already used by
# modules/storage), and querying it would compare against reality rather than a
# declaration. It would also make `tofu validate` and `tofu test` require
# credentials and a reachable cluster, which is exactly the fast, offline loop
# this repo runs in pre-commit and CI. modules/storage records a previous
# attempt down that road being reverted for a related reason (the provider does
# not mark `datastores` computed, so it is incompatible with `tofu test`).
#
# So this compares the declaration against `node_storage`, the desired-state
# declaration of which pools exist on which node, plus the datastores every PVE
# node has out of the box. That is strictly weaker than asking the cluster, and
# it still rejects the case above, because the whole point is that `fast` was
# never declared on that node.
#
# NOT a `check` block: a failed check only WARNS and the plan still exits 0
# (see the note in checks.tf), so the guard would look present and do nothing.

locals {
  # Datastores present on every PVE node without being declared: the packaged
  # directory store and the rpool-backed ZFS store the installer creates. They
  # are legitimate targets and never appear in node_storage.pools, so a check
  # that omitted them would reject most of the estate.
  builtin_node_datastores = ["local", "local-zfs"]

  # Datastore ids usable on each node. A pool is only reachable as a Proxmox
  # datastore once it is registered with pvesm, so `register = false` pools —
  # real ZFS pools that PVE does not expose as storage, e.g. an rpool declared
  # only so its properties are managed — are deliberately excluded.
  node_usable_datastores = {
    for node, cfg in var.node_storage : node => concat(
      local.builtin_node_datastores,
      [for pool_name, pool in cfg.pools : pool_name if pool.register]
    )
  }

  # Every datastore reference a container makes, flattened with enough context
  # to name the offending attribute in the error.
  #
  # A mount point with no `size` is a HOST BIND-MOUNT: `volume` is a path on the
  # node, not a datastore id, so it is exempt. Likewise a null
  # root_disk.datastore_id, which means "let the provider choose".
  container_datastore_refs = flatten([
    for name, c in var.containers : concat(
      try(c.root_disk.datastore_id, null) == null ? [] : [{
        container = name
        node      = c.node_name
        datastore = c.root_disk.datastore_id
        attribute = "root_disk.datastore_id"
      }],
      [
        for idx, mp in coalesce(c.mount_points, []) : {
          container = name
          node      = c.node_name
          datastore = mp.volume
          attribute = "mount_points[${idx}].volume"
        } if mp.size != null
      ]
    )
  ])

  # Only judge containers whose node declares storage at all. A node absent from
  # node_storage has nothing to compare against, and rejecting every guest on it
  # would be a guess rather than a finding.
  invalid_container_datastore_refs = [
    for ref in local.container_datastore_refs : ref
    if contains(keys(var.node_storage), ref.node)
    && !contains(local.node_usable_datastores[ref.node], ref.datastore)
  ]

  invalid_container_datastore_messages = [
    for ref in local.invalid_container_datastore_refs :
    "${ref.container}.${ref.attribute} = \"${ref.datastore}\" but node ${ref.node} offers only [${join(", ", sort(local.node_usable_datastores[ref.node]))}]"
  ]
}

# terraform_data is a provider-less plan-time anchor; the precondition is the
# whole point of the resource. Same shape as the OpenBao voter guard.
resource "terraform_data" "container_datastore_guard" {
  input = length(local.invalid_container_datastore_refs)

  lifecycle {
    precondition {
      condition     = length(local.invalid_container_datastore_refs) == 0
      error_message = "Container storage names a datastore that does not exist on its node. Proxmox will not fail this — it silently places the volume on another datastore, and mount_point is in ignore_changes so no later plan reports the drift. Offending references:\n  ${join("\n  ", local.invalid_container_datastore_messages)}\nFix the declaration, or declare the pool on that node in node_storage with register = true."
    }
  }
}
