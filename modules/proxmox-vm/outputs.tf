output "vm_ids" {
  description = "Map of VM names to their IDs"
  value       = { for k, v in proxmox_virtual_environment_vm.vms : k => v.vm_id }
}

output "vm_names" {
  description = "Map of VM keys to their names"
  value       = { for k, v in proxmox_virtual_environment_vm.vms : k => v.name }
}

output "vm_details" {
  description = "Complete VM information"
  value = { for k, v in proxmox_virtual_environment_vm.vms : k => {
    id          = v.vm_id
    name        = v.name
    node_name   = v.node_name
    description = v.description
    tags        = v.tags
    pool_id     = v.pool_id
    # The VM's live first-NIC MAC. Deliberately NOT v.mac_addresses: that list is
    # reported by the guest agent and enumerates every interface the OS has, so on
    # a docker host it churns with each container veth. network_device[0] is the
    # configured NIC and is stable.
    #
    # Lower-cased for the same reason as the container output: the API answers in
    # upper case, local.vm_mac builds lower case, and the artifact should not flip
    # case on already-published guests.
    mac_address = try(lower(v.network_device[0].mac_address), null)
    # Every disk this VM actually has, with the volume name PROXMOX assigned.
    #
    # READ from the provider, never assigned — the same contract as mac_address
    # above, for the same reason: Proxmox owns the value. `path_in_datastore` is
    # a computed attribute (`vm-250-disk-1`), and it is the ONLY honest source
    # for it.
    #
    # Do NOT derive these names by counting declared disks. Indices are
    # allocated per (vmid, storage) as next-free, so a count-derivation is wrong
    # wherever a volume was ever moved: VM 200 today has fast:vm-200-disk-0 as
    # the RETAINED pre-move rollback and fast:vm-200-disk-1 as the live cold
    # disk. Counting would name disk-0 and point a snapshot policy at a frozen
    # copy — the exact false green this field exists to prevent.
    #
    # A list, not one entry: a VM's data usually is not on its boot disk. Docker
    # VM 250 keeps 100G on a second disk, and publishing only the boot disk
    # would advertise coverage that misses the data.
    disks = [for d in v.disk : {
      datastore = d.datastore_id
      # e.g. "vm-250-disk-1" — combine as "<datastore-root>/<path>" to get the
      # ZFS dataset. Consumers must NOT prepend a pool name of their own.
      path      = d.path_in_datastore
      interface = d.interface
    }]
  } }
}

output "vm_network_interfaces" {
  description = "VM network interface information"
  value = { for k, v in proxmox_virtual_environment_vm.vms : k => {
    ipv4_addresses          = v.ipv4_addresses
    ipv6_addresses          = v.ipv6_addresses
    mac_addresses           = v.mac_addresses
    network_interface_names = v.network_interface_names
  } }
}
