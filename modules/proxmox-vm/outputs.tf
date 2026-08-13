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
