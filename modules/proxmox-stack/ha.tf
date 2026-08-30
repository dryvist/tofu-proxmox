# Proxmox HA, declared here rather than in Ansible.
#
# WHY HERE. The estate's HA has lived in ansible-proxmox's `pve_ha` role since
# before the provider supported it. That is an accident of timing, not an
# ownership boundary: AGENTS.md already calls this repo "the single source of
# truth for infrastructure: VMs, containers, IPs, ports, and firewall rules",
# and which node a guest survives on is infrastructure. bpg/proxmox ~> 0.111 —
# already pinned — ships proxmox_haresource and proxmox_harule (PVE 9 HA rules,
# which replaced legacy HA groups), so nothing new is needed to say it here,
# next to the guest it applies to.
#
# Migrating the existing tier-0 keystones (traefik, the technitium pair, the
# OpenBao voters) off `pve_ha` onto these resources is a follow-up. Until then
# the two coexist: this file only touches guests that opt in with `ha = true`,
# and nothing in the estate does by default.
#
# THE HAZARD, restated because opting a guest in accepts it. imports.tf
# documents the loop in full: HA relocates a guest, refresh looks it up on the
# node recorded in STATE, 404s, drops the resource and plans a CREATE that can
# never succeed against a cluster-unique VMID. The apply then fails and takes
# aws_s3_object.ansible_inventory with it, freezing the published inventory all
# three consumer repos read. Enrol a guest whose state cannot be rebuilt from
# code; do not enrol one that can.

locals {
  # Guests that opted in. Keyed by container key so the HA resource address is
  # stable across a VMID change.
  ha_containers = {
    for k, v in var.containers : k => v if try(v.ha, false)
  }

  # Negative-affinity groups: {group_name => [ct:vmid, ...]}. A group with a
  # single member is dropped — a one-member anti-affinity rule constrains
  # nothing and Proxmox rejects some degenerate forms outright.
  ha_affinity_members = {
    for group in distinct([
      for v in values(local.ha_containers) : v.ha_affinity_group
      if try(v.ha_affinity_group, null) != null
    ]) : group => sort([
      for v in values(local.ha_containers) : "ct:${v.vm_id}"
      if try(v.ha_affinity_group, null) == group
    ])
  }

  ha_affinity_rules = {
    for group, members in local.ha_affinity_members : group => members
    if length(members) > 1
  }
}

resource "proxmox_haresource" "containers" {
  for_each = local.ha_containers

  resource_id = "ct:${each.value.vm_id}"
  state       = "started"
  comment     = "Managed by OpenTofu — ${each.value.hostname}"

  # Restart in place a few times before relocating: a relocation is what
  # desynchronises this repo's state, so it should be the second resort.
  max_restart  = 3
  max_relocate = 1

  # The guest must exist before HA can manage it.
  depends_on = [module.containers]
}

resource "proxmox_harule" "container_anti_affinity" {
  for_each = local.ha_affinity_rules

  rule      = "${each.key}-apart"
  type      = "resource-affinity"
  affinity  = "negative"
  resources = each.value
  comment   = "Managed by OpenTofu — keep ${each.key} members on separate nodes"

  # "The resources must already be managed by HA" — provider docs.
  depends_on = [proxmox_haresource.containers]
}
