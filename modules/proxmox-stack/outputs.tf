# SSH key outputs
output "vm_ssh_public_key" {
  description = "SSH public key used for VMs and containers"
  value       = trimspace(var.vm_ssh_public_key)
}

output "vm_ssh_key_file" {
  description = "Deprecated: remote Terrakube execution uses key content, not a workstation path"
  value       = null
}

# Pool outputs
output "pools" {
  description = "Created resource pools"
  value       = module.pools.pools
}

# Storage outputs
output "cloud_init_file_id" {
  description = "Cloud-init configuration file ID"
  value       = module.storage.cloud_init_file_id
}

output "storage_validated" {
  description = "Confirms storage data sources are loaded"
  value       = module.storage.storage_validated
}

# VM outputs
output "vms" {
  description = "Created VMs information"
  value       = module.vms.vm_details
}

# Container outputs (when enabled)
output "containers" {
  description = "Created containers information"
  value       = length(var.containers) > 0 ? module.containers[0].container_details : {}
}

output "container_network_info" {
  description = "Container network interface information"
  value       = length(var.containers) > 0 ? module.containers[0].container_network_interfaces : {}
}

# NOTE: Route53 DNS outputs are now in aws-infra/outputs.tf

# ACME Certificate outputs
output "acme_certificates" {
  description = "ACME certificates information"
  value       = try(module.acme_certificates[0].certificates, {})
}

output "acme_accounts" {
  description = "ACME accounts information"
  value       = try(module.acme_certificates[0].acme_accounts, {})
}

output "acme_dns_plugins" {
  description = "DNS plugins for ACME validation"
  value       = try(module.acme_certificates[0].dns_plugins, {})
  sensitive   = true
}

# Ansible Inventory Output - Single Source of Truth
# This output structures all infrastructure data for dynamic Ansible inventory
# generation, eliminating hardcoded VM IDs and IPs from Ansible configuration.
output "ansible_inventory" {
  description = "Structured inventory for Ansible consumption - includes all VMs, containers, and Splunk infrastructure"
  # The value lives in local.ansible_inventory (inventory_publish.tf) so the
  # native aws_s3_object publish resource can reference the same data — a
  # resource cannot reference an output.
  value = local.ansible_inventory
}

# Rack-server cluster inventory - NO consumer yet. When one materializes, it
# should fetch a published S3 artifact (the ansible_inventory pattern in
# inventory_publish.tf), not terraform_remote_state — consumers must not need
# the toolchain or full state read access.
# Sensitive: BMC IPs/MACs and host mgmt IPs are operational secrets. A consumer
# must use nonsensitive() when constructing inventory strings from these.
output "rack_servers" {
  description = "Rack-server identity (names, BMC IPs/MACs, mgmt IPs, service tags, by-chassis grouping, ansible inventory shape). Real values come from private RustFS deployment object; when var.rack_servers defaults to an empty map, this output is an object whose collections are all empty."
  value = {
    names             = module.rack_server_cluster.node_names
    bmc_ips           = module.rack_server_cluster.bmc_ips
    bmc_macs          = module.rack_server_cluster.bmc_macs
    mgmt_ips          = module.rack_server_cluster.mgmt_ips
    service_tags      = module.rack_server_cluster.service_tags
    by_chassis        = module.rack_server_cluster.by_chassis
    ansible_inventory = module.rack_server_cluster.ansible_inventory
  }
  sensitive = true
}
