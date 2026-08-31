# Inventory assembly, virtual-machine half.
#
# Split out of inventory_assembly.tf, which crossed the repository's hard
# file-size gate. The container half already lives in inventory_containers.tf,
# so this mirrors an existing split rather than inventing a layout; the map
# literal in inventory_assembly.tf now references both by name.
#
# The reads below are PLAIN attribute reads, deliberately, not try(). Reading an
# attribute here is what keeps it declared, and an undeclared attribute is
# silently stripped from the desired state rather than raising. Wrapping any of
# them in try() would restore that silent-strip behaviour.

locals {
  inventory_vms = {
    for k, v in module.vms.vm_details : k => {
      vmid               = v.id
      hostname           = v.name
      ip                 = local.vm_address[k]
      mac                = v.mac_address
      node               = v.node_name
      ansible_connection = try(var.vms[k].ansible_connection, "ssh")
      # Whether the guest is expected to be running. A guest only an operator
      # may power on publishes started = false, so a converge can skip it
      # instead of failing against a host that is deliberately switched off.
      # Reading these here is also what keeps them declared. They are plain
      # attribute reads, not `try()`, so dropping either from var.vms breaks
      # the PLAN instead of silently reverting every guest to the default.
      # `tofu validate` still passes in that state - checked - so the guard
      # that actually bites is the contract test, which asserts both through
      # this output.
      on_boot = var.vms[k].on_boot
      started = var.vms[k].started
      # Same sizing contract as the containers block above, for the same
      # reason: Nautobot models vcpus/memory/disk natively and a guest without
      # them reads null. Publishing it for containers ONLY left the actual VMs
      # — the guests the field name refers to — still blank.
      #
      # boot_disk.size rather than root_disk.size: a VM's system disk is
      # boot_disk here, and additional_disks are deliberately excluded because
      # Nautobot's `disk` is a single number, not a sum. Recording a total
      # would silently disagree with what the guest calls its disk.
      cpu_cores = var.vms[k].cpu_cores
      memory_mb = var.vms[k].memory_dedicated
      disk_gb   = var.vms[k].boot_disk.size
      # WHERE the boot disk lives, same contract as the containers block and
      # for the same reason: a consumer that snapshots this guest's dataset
      # must resolve its pool rather than hardcode one. pve-w1700's sanoid
      # policy named `rpool/data/vm-200-disk-0` literally, which is Splunk's
      # own disk -- a tier move would leave it snapshotting a stale dataset
      # while counts and timestamps stayed healthy.
      #
      # A PLAIN read, unlike the containers block: boot_disk.datastore_id is
      # optional(string, "local-lvm"), so it carries a default and is never
      # null. A coalesce here would be dead code implying a nullability the
      # type does not have.
      datastore = var.vms[k].boot_disk.datastore_id
      # EVERY disk, with the volume name Proxmox assigned -- read back from
      # the provider (see modules/proxmox-vm/outputs.tf). `datastore` above is
      # the BOOT disk only, and a VM's data usually is not on its boot disk:
      # docker VM 250 keeps 100G on a second disk. A consumer that snapshots
      # this guest must iterate `disks`, not assume `datastore`.
      disks = v.disks
      # The guest's own LAN gateway. Published because a guest running a VPN
      # client cannot discover it at converge time: the client owns the
      # default route by then, so "the current gateway" is the tunnel's.
      #
      # vm_lan_gateway, NOT vm_gateway: the latter is the cloud-init value and
      # is null for DHCP-first guests, which is nearly the whole estate. The
      # VLAN's gateway is well defined either way and is what DHCP hands out.
      gateway = local.vm_lan_gateway[k]
      tags    = v.tags
      pool_id = v.pool_id
      # The node holding this guest's replica, published so the HA layer can
      # derive its relocation target from the desired state instead of carrying
      # a node name of its own. A PLAIN read, not try(): reading it here is what
      # keeps the attribute DECLARED, and an undeclared attribute is silently
      # stripped from the desired state rather than erroring.
      ha_replication_target = var.vms[k].ha_replication_target
    }
  }

  inventory_docker_vms = {
    for k, v in module.vms.vm_details : k => {
      vmid               = v.id
      hostname           = v.name
      ip                 = local.vm_address[k]
      mac                = v.mac_address
      node               = v.node_name
      ansible_connection = "ssh"
      tags               = v.tags
      pool_id            = v.pool_id
      # docker_vms is a FILTERED VIEW of the same vms map, so it needs the
      # same sizing and placement reads -- a guest does not stop having a size
      # or a datastore because it is republished under a second key.
      cpu_cores = var.vms[k].cpu_cores
      memory_mb = var.vms[k].memory_dedicated
      disk_gb   = var.vms[k].boot_disk.size
      datastore = var.vms[k].boot_disk.datastore_id
      disks     = v.disks
      # The node holding this guest's replica, published so the HA layer can
      # derive its relocation target from the desired state instead of carrying
      # a node name of its own. A PLAIN read, not try(): reading it here is what
      # keeps the attribute DECLARED, and an undeclared attribute is silently
      # stripped from the desired state rather than erroring.
      ha_replication_target = var.vms[k].ha_replication_target
    } if contains(try(v.tags, []), "docker")
  }
}
