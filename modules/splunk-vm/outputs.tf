output "vm_id" {
  description = "The VM ID of the Splunk VM"
  value       = proxmox_virtual_environment_vm.splunk_vm.vm_id
}

output "name" {
  description = "The name of the Splunk VM"
  value       = proxmox_virtual_environment_vm.splunk_vm.name
}

output "ip_address" {
  description = "The IPv4 address of the Splunk VM (first non-loopback interface)"
  value = length(proxmox_virtual_environment_vm.splunk_vm.ipv4_addresses) > 1 ? (
    length(proxmox_virtual_environment_vm.splunk_vm.ipv4_addresses[1]) > 0 ?
    split("/", proxmox_virtual_environment_vm.splunk_vm.ipv4_addresses[1][0])[0] : null
  ) : null
}

output "mac_address" {
  description = "The MAC address of the Splunk VM network interface"
  value       = length(proxmox_virtual_environment_vm.splunk_vm.mac_addresses) > 0 ? proxmox_virtual_environment_vm.splunk_vm.mac_addresses[0] : null
}

output "tiered_disks" {
  description = "Tiered Splunk data disks (fast-splunk/bulk-splunk) as declared, keyed by tier."
  value       = var.tiered_disks
}

output "disks" {
  description = "Every Splunk VM disk with the volume name Proxmox assigned, read back from the provider."
  # DECLARED values are not enough, and tiered_disks above is exactly that --
  # it is literally var.tiered_disks. It carries no volume NAME, so a consumer
  # that needs this guest's ZFS dataset (a snapshot policy) cannot build one.
  #
  # `path_in_datastore` is a COMPUTED attribute: Proxmox owns the value. Same
  # contract as mac_address above -- read from the provider, never assigned.
  #
  # Deriving these names by counting disks is WRONG, and THIS guest is the
  # proof: indices are allocated per (vmid, storage) as next-free, so
  # `fast:vm-200-disk-0` is the RETAINED pre-move rollback while
  # `fast:vm-200-disk-1` is the LIVE cold disk. A count-derivation names disk-0
  # and points the snapshot policy at a frozen copy -- healthy counts, current
  # timestamps, zero live data captured.
  value = [for d in proxmox_virtual_environment_vm.splunk_vm.disk : {
    datastore = d.datastore_id
    path      = d.path_in_datastore
    interface = d.interface
  }]
}
