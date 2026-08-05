# Security Group: RDP Services
resource "proxmox_virtual_environment_cluster_firewall_security_group" "rdp_services" {
  name    = "rdp-services"
  comment = "Managed by Terraform: Allow RDP access from internal networks"

  rule {
    action  = "ACCEPT"
    type    = "in"
    macro   = "RDP"
    source  = join(",", var.internal_networks)
    comment = "Allow RDP from internal networks"
  }
}

# RDP VMs Firewall Configuration
resource "proxmox_virtual_environment_firewall_options" "rdp_vms" {
  for_each = var.rdp_vm_ids

  node_name = var.node_name
  vm_id     = each.value

  enabled = true

  # Default policy
  input_policy  = "DROP"
  output_policy = "DROP"

  # Anti-spoofing and logging
  macfilter     = true
  log_level_in  = "nolog"
  log_level_out = "nolog"
}

resource "proxmox_virtual_environment_firewall_rules" "rdp_vms" {
  for_each = var.rdp_vm_ids

  node_name = var.node_name
  vm_id     = each.value

  # Standard internal access
  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.internal_access.name
    comment        = "Allow standard internal access (SSH, ICMP)"
  }

  # Standard outbound internal
  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.outbound_internal.name
    comment        = "Allow outbound to internal networks"
  }

  # Standard outbound internet
  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.outbound_https.name
    comment        = "Allow outbound HTTPS"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.outbound_http.name
    comment        = "Allow outbound HTTP"
  }

  # RDP Services
  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.rdp_services.name
    comment        = "Allow RDP access"
  }

  depends_on = [
    proxmox_virtual_environment_firewall_options.rdp_vms
  ]
}
