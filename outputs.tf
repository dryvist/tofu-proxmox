# Root outputs pass modules/proxmox-root's outputs through unchanged;
# descriptions mirror modules/proxmox-stack/outputs.tf.
output "vm_ssh_public_key" {
  description = "SSH public key used for VMs and containers"
  value       = module.stack.vm_ssh_public_key
}
output "vm_ssh_key_file" {
  description = "Deprecated: remote Terrakube execution uses key content, not a workstation path"
  value       = module.stack.vm_ssh_key_file
}
output "pools" {
  description = "Created resource pools"
  value       = module.stack.pools
}
output "cloud_init_file_id" {
  description = "Cloud-init configuration file ID"
  value       = module.stack.cloud_init_file_id
}
output "storage_validated" {
  description = "Confirms storage data sources are loaded"
  value       = module.stack.storage_validated
}
output "vms" {
  description = "Created VMs information"
  value       = module.stack.vms
}
output "vm_network_info" {
  description = "VM network interface information"
  value       = module.stack.vm_network_info
}
output "containers" {
  description = "Created containers information"
  value       = module.stack.containers
}
output "container_network_info" {
  description = "Container network interface information"
  value       = module.stack.container_network_info
}
output "acme_certificates" {
  description = "ACME certificates information"
  value       = module.stack.acme_certificates
}
output "acme_accounts" {
  description = "ACME accounts information"
  value       = module.stack.acme_accounts
}
output "acme_dns_plugins" {
  description = "DNS plugins for ACME validation"
  value       = module.stack.acme_dns_plugins
  sensitive   = true
}
output "ansible_inventory" {
  description = "Structured inventory for Ansible consumption"
  value       = module.stack.ansible_inventory
}
output "rack_servers" {
  description = "Rack-server identity and inventory grouping"
  value       = module.stack.rack_servers
  sensitive   = true
}
