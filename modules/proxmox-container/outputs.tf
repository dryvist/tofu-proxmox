output "container_ids" {
  description = "Map of container names to their IDs"
  value       = { for k, v in proxmox_virtual_environment_container.containers : k => v.vm_id }
}

output "container_details" {
  description = "Complete container information"
  value = { for k, v in proxmox_virtual_environment_container.containers : k => {
    id          = v.vm_id
    node_name   = v.node_name
    description = v.description
    tags        = v.tags
    pool_id     = v.pool_id
    # The guest's live first-NIC MAC, whether we assigned it or the provider did.
    # `mac_address` is optional+computed, so this reads back the auto-generated
    # address on static guests instead of reassigning one - nothing on a running
    # container changes because this is published.
    #
    # Lower-cased because the API returns upper-case while local.container_mac
    # builds lower-case: without this, publishing the computed value would flip
    # the case of every DHCP guest's MAC and churn the artifact for no reason.
    mac_address = try(lower(v.network_interface[0].mac_address), null)
  } }
}

output "container_network_interfaces" {
  description = "Container network interface configuration (computed attributes not available in bpg/proxmox v0.90+)"
  value = { for k, v in proxmox_virtual_environment_container.containers : k => {
    # Note: In bpg/proxmox v0.90+, network attributes (ipv4_addresses, mac_addresses, etc.)
    # are not exposed as computed attributes. Use 'tofu show' to view runtime network details.
    configured_interfaces = length(v.network_interface)
  } }
}
