# Outputs pass the inner module's outputs through unchanged; descriptions
# mirror modules/proxmox-stack/outputs.tf. `deployment` and `containers` are
# additional: ../imports.tf (root-only, so it cannot live in this module)
# resolves its import ids against these instead of the locals it read
# directly before this composition moved into a module.
output "vm_ssh_public_key" {
  description = "SSH public key used for VMs and containers"
  value       = module.homelab.vm_ssh_public_key
}
output "vm_ssh_key_file" {
  description = "Deprecated: remote Terrakube execution uses key content, not a workstation path"
  value       = module.homelab.vm_ssh_key_file
}
output "pools" {
  description = "Created resource pools"
  value       = module.homelab.pools
}
output "cloud_init_file_id" {
  description = "Cloud-init configuration file ID"
  value       = module.homelab.cloud_init_file_id
}
output "storage_validated" {
  description = "Confirms storage data sources are loaded"
  value       = module.homelab.storage_validated
}
output "vms" {
  description = "Created VMs information"
  value       = module.homelab.vms
}
output "vm_network_info" {
  description = "VM network interface information"
  value       = module.homelab.vm_network_info
}
output "containers" {
  description = "Merged container map (deployment.json containers + generated OpenBao voters + generated per-node services) — the same map passed into modules/proxmox-stack, needed by ../imports.tf to resolve import ids."
  value       = local.containers
}
output "container_network_info" {
  description = "Container network interface information"
  value       = module.homelab.container_network_info
}
output "acme_certificates" {
  description = "ACME certificates information"
  value       = module.homelab.acme_certificates
}
output "acme_accounts" {
  description = "ACME accounts information"
  value       = module.homelab.acme_accounts
}
output "acme_dns_plugins" {
  description = "DNS plugins for ACME validation"
  value       = module.homelab.acme_dns_plugins
  sensitive   = true
}
output "ansible_inventory" {
  description = "Structured inventory for Ansible consumption"
  value       = module.homelab.ansible_inventory
}
output "rack_servers" {
  description = "Rack-server identity and inventory grouping"
  value       = module.homelab.rack_servers
  sensitive   = true
}
output "deployment" {
  description = "Decoded deployment object, needed by ../imports.tf to resolve import ids."
  value       = local.deployment
}
