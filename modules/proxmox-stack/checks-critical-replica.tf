# A guest marked critical must have somewhere to fail over to.
#
# `critical = true` says this guest's loss stops other services, so its
# declaration may never rest on one node's local storage. Two declarations
# actually give it that: HA enrolment plus a pvesr replica on ANOTHER node
# (ha_replication_target — the only node HA may relocate the guest to on node
# loss), or HA enrolment plus a negative-affinity group with a second member
# (ha.tf creates the proxmox_harule only for groups with two or more members,
# and Proxmox keeps negative-affinity members on separate nodes). Everything
# else — critical with ha off, a replica naming the guest's own node, a group
# whose second member never enrolled in HA — leaves the guest on single-node
# storage no matter what the declaration claims.
#
# Enforced at plan time so a declaration that drops the replica cannot merge:
# the rule rides on the guest map itself, and a plan that marks a guest
# critical without naming its failover fails before any resource is touched.
#
# NOT a `check` block: a failed check only WARNS and the plan still exits 0
# (see the note in checks.tf), so the guard would look present and do nothing.

locals {
  # Guests enrolled in HA. Membership in an affinity group is counted over
  # these only, mirroring ha.tf: a Proxmox HA rule constrains nothing among
  # guests HA does not manage, so a non-HA guest sharing the group name is not
  # a member any more than a guest of another deployment would be.
  critical_ha_guests = {
    for name, guest in var.containers : name => guest if try(guest.ha, false)
  }

  critical_affinity_group_sizes = {
    for group in distinct([
      for guest in values(local.critical_ha_guests) : guest.ha_affinity_group
      if try(guest.ha_affinity_group, null) != null
      ]) : group => length([
      for guest in values(local.critical_ha_guests) :
      guest if guest.ha_affinity_group == group
    ])
  }

  # A critical guest survives the loss of its own node only when HA is on AND
  # the guest either carries a replica on a different node, or shares an
  # affinity group with at least one other HA-enrolled guest.
  critical_guests_without_replica = sort([
    for name, guest in var.containers : name
    if try(guest.critical, false) && !(
      try(guest.ha, false) && (
        (
          try(guest.ha_replication_target, null) != null &&
          guest.ha_replication_target != "" &&
          guest.ha_replication_target != guest.node_name
          ) || (
          try(guest.ha_affinity_group, null) != null &&
          local.critical_affinity_group_sizes[guest.ha_affinity_group] >= 2
        )
      )
    )
  ])
}

# terraform_data is a provider-less plan-time anchor; the precondition is the
# whole point of the resource. Same shape as the container datastore guard.
resource "terraform_data" "critical_replica_guard" {
  input = length(local.critical_guests_without_replica)

  lifecycle {
    precondition {
      condition     = length(local.critical_guests_without_replica) == 0
      error_message = "Guests marked critical = true must survive the loss of their own node. For each guest below, set ha = true and give ha_replication_target a node different from its node_name, or set ha = true and give it an ha_affinity_group shared with at least one other ha = true guest. Offending guests: ${join(", ", local.critical_guests_without_replica)}."
    }
  }
}
