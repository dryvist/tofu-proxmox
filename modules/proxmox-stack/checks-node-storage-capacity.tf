# A pool's declared quotas must fit the pool.
#
# A ZFS quota is a cap, not a reservation, so nothing stops a pool from carrying
# quotas that sum past what it can hold — and nothing reports it. The failure is
# silent in both directions, which is what earns a hard guard:
#
#   TOO SMALL: a quota outlives the pool it was written for. One dataset here
#   carried a quota sized for a three-device pool that had since been expanded
#   to six. It read 90% full with terabytes free underneath, and a week of work
#   went into reclaiming space that was never the constraint.
#
#   TOO LARGE: quotas that sum past capacity stop being guards at all. The pool
#   fills, every dataset is still under its own quota, and the first symptom is
#   ENOSPC in whichever workload happens to write next.
#
# Both cases are checkable the moment the pool's shape is declared, so the
# `topology` a pool already declares for the ansible-side vdev assertion is
# reused here to derive capacity. Declaring `device_size` opts a pool in; a pool
# that omits it is not checked rather than guessed at.
#
# NOT a `check` block: a failed check only WARNS and the plan still exits 0 (see
# the note in checks.tf), so the guard would look present and do nothing. NOT a
# variable `validation` either, because the arithmetic needs intermediate values
# and a validation block cannot reference locals.
#
# Deliberately STATIC, for the same reason as checks-storage.tf: comparing
# against the live pool would make `tofu validate` and `tofu test` require
# credentials and a reachable cluster, and this repo's fast offline loop is
# worth more than the extra fidelity. This compares the declaration against
# itself, which is strictly weaker than asking the cluster and still rejects
# both failures above.

locals {
  storage_unit_bytes = {
    ""  = 1
    "K" = 1024
    "M" = 1048576
    "G" = 1073741824
    "T" = 1099511627776
    "P" = 1125899906842624
  }

  # Devices consumed by parity, per vdev type. A mirror is handled separately
  # below: its usable capacity is one device regardless of width, so it does not
  # fit the "width minus parity" shape. draid is absent on purpose — its usable
  # capacity depends on the data/parity/spare split encoded in the vdev name,
  # which `topology` does not carry, so a draid pool goes unchecked rather than
  # be checked against a number this file would have to invent.
  zfs_parity_devices = {
    raidz1 = 1
    raidz2 = 2
    raidz3 = 3
  }

  # Every size string in the declaration, parsed exactly once. Sizes are ZFS
  # canonical forms ("15T", "400G", "5.46T"), so a leading number and an
  # optional binary unit is the whole grammar.
  node_storage_size_strings = distinct(concat(
    flatten([
      for node, cfg in var.node_storage : [
        for pool_name, pool in cfg.pools : [
          for ds_name, ds in pool.datasets : ds.quota if ds.quota != null
        ]
      ]
    ]),
    compact(flatten([
      for node, cfg in var.node_storage : [
        for pool_name, pool in cfg.pools : try(pool.topology.device_size, null)
      ]
    ]))
  ))

  node_storage_size_bytes = {
    for s in local.node_storage_size_strings : s =>
    tonumber(regex("^([0-9.]+)([KMGTP]?)", upper(s))[0]) *
    local.storage_unit_bytes[regex("^([0-9.]+)([KMGTP]?)", upper(s))[1]]
  }

  # Pools that declared enough to be judged: a topology, a device size, and a
  # vdev type whose geometry this file actually knows.
  checkable_storage_pools = merge([
    for node, cfg in var.node_storage : {
      for pool_name, pool in cfg.pools : "${node}/${pool_name}" => {
        node     = node
        pool     = pool_name
        topology = pool.topology

        # Only quotas with no quota'd ANCESTOR in the same pool. A child
        # dataset's usage already counts against every quota above it, so
        # summing both double-counts the child and would reject a declaration
        # the pool can actually hold. `bulk/data` at 15T with `bulk/data/seed`
        # capped at 1T underneath consumes 15T, not 16T.
        #
        # An unquota'd dataset between two quota'd ones changes nothing: the
        # test is whether ANY ancestor caps this path, not the nearest one.
        quotas = [
          for ds_name, ds in pool.datasets : ds.quota
          if ds.quota != null && !anytrue([
            for ancestor_name, ancestor in pool.datasets :
            ancestor.quota != null
            && ancestor_name != ds_name
            && startswith(ds_name, "${ancestor_name}/")
          ])
        ]
      }
      if pool.topology != null
      && try(pool.topology.device_size, null) != null
      && (pool.topology.type == "mirror" || contains(keys(local.zfs_parity_devices), pool.topology.type))
    }
  ]...)

  storage_pool_capacity = {
    for key, p in local.checkable_storage_pools : key => {
      node = p.node
      pool = p.pool

      # concat([0], ...) because sum() rejects an empty list, and a pool whose
      # datasets declare no quota at all is legitimate.
      declared_bytes = sum(concat([0], [
        for q in p.quotas : local.node_storage_size_bytes[q]
      ]))

      # ZFS withholds 1/32 of the pool as slop space and will not let the last
      # of it be consumed, so the honest ceiling is 31/32 of the raw usable
      # figure. This still ignores raidz parity padding, which costs more at
      # small recordsizes — so the number is an upper bound on what the pool can
      # really hold, and a declaration that fails this check would have failed a
      # more exact one too.
      usable_bytes = floor(
        (p.topology.type == "mirror"
          ? 1
        : p.topology.width - local.zfs_parity_devices[p.topology.type])
        * local.node_storage_size_bytes[p.topology.device_size]
        * 31 / 32
      )
    }
  }

  overcommitted_storage_pools = [
    for key, c in local.storage_pool_capacity : c
    if c.declared_bytes > c.usable_bytes
  ]

  overcommitted_storage_messages = [
    for c in local.overcommitted_storage_pools :
    format(
      "%s/%s declares %.2f TiB of dataset quota against %.2f TiB usable",
      c.node, c.pool,
      c.declared_bytes / 1099511627776,
      c.usable_bytes / 1099511627776,
    )
  ]
}

# terraform_data is a provider-less plan-time anchor; the precondition is the
# whole point of the resource. Same shape as the container datastore guard.
resource "terraform_data" "node_storage_capacity_guard" {
  input = length(local.overcommitted_storage_pools)

  lifecycle {
    precondition {
      condition     = length(local.overcommitted_storage_pools) == 0
      error_message = "Declared dataset quotas exceed the pool's usable capacity at its declared topology. A quota is a cap and not a reservation, so ZFS accepts this and the pool simply fills — every dataset still under its own quota, and the first symptom is a write failure in whichever workload got there last. Offending pools:\n  ${join("\n  ", local.overcommitted_storage_messages)}\nEither lower a dataset quota, or correct topology.width/device_size if the pool's shape changed."
    }
  }
}
