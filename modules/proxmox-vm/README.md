# Proxmox VM Module

This module creates and manages virtual machines on Proxmox VE.

## Features

- ✅ Comprehensive VM configuration with sensible defaults
- ✅ Flexible network interface configuration
- ✅ Cloud-init support for automated provisioning
- ✅ Boot disk and additional disk management
- ✅ Resource pool integration
- ✅ Agent configuration and protection settings

## Usage

### Basic VM

```hcl
module "vms" {
  source = "./modules/proxmox-vm"

  vms = {
    "web-server" = {
      vm_id       = 201
      name        = "web-server"
      description = "Web server VM"
      node_name   = "proxmox-1"

      cpu_cores        = 2
      memory_dedicated = 2048

      boot_disk = {
        size      = 20
        interface = "virtio0"  # Recommended for performance and compatibility
      }

      ip_config = {
        ipv4_address = "192.168.1.100/24"
        ipv4_gateway = "192.168.1.1"
      }

      user_account = {
        username = "debian"
        password = "secure-password"
        keys     = ["ssh-rsa AAAAB3..."]
      }
    }
  }

  environment = "production"
}
```

### Advanced VM with Multiple Disks

```hcl
module "vms" {
  source = "./modules/proxmox-vm"

  vms = {
    "database-server" = {
      vm_id       = 301
      name        = "database-server"
      node_name   = "proxmox-1"
      pool_id     = "database-pool"

      cpu_cores        = 4
      cpu_type         = "x86-64-v2-AES"
      memory_dedicated = 8192
      memory_floating  = 1024

      boot_disk = {
        datastore_id = "ssd-storage"
        size         = 40
        ssd          = true
      }

      additional_disks = [
        {
          datastore_id = "hdd-storage"
          size         = 500
          interface    = "virtio1"  # Use virtio for additional disks too
        }
      ]

      network_interfaces = [
        {
          bridge   = "vmbr0"
          model    = "virtio"
          firewall = true
        },
        {
          bridge  = "vmbr1"
          vlan_id = 100
        }
      ]
    }
  }
}
```

## Input Variables

| Name | Description | Type | Required | Default |
| ------ | ------------- | ------ | ---------- | --------- |
| `vms` | Map of VMs to create | `map(object)` | ✅ | `{}` |
| `environment` | Environment name for tagging | `string` | ✅ | - |
| `default_datastore` | Default datastore for VMs | `string` | ❌ | `"local-lvm"` |
| `proxmox_api_token` | Proxmox API token | `string` | ✅ | - |
| `proxmox_api_endpoint` | Proxmox API endpoint | `string` | ✅ | - |
| `proxmox_user` | Proxmox login user (no realm) | `string` | ✅ | n/a |
| `proxmox_ssh_private_key` | SSH private key | `string` | ✅ | - |

### VM Object Schema

```hcl
{
  vm_id       = number           # VM ID (100-999999999)
  name        = string           # VM name
  description = optional(string) # VM description
  tags        = optional(list(string), ["terraform"])
  pool_id     = optional(string) # Resource pool ID

  # Node configuration
  node_name = string             # Proxmox node name

  # Resource configuration
  cpu_cores        = optional(number, 2)    # CPU cores (1-32)
  cpu_type         = optional(string, "x86-64-v2-AES")
  memory_dedicated = optional(number, 1024) # RAM in MB (256-65536)
  memory_floating  = optional(number)       # Floating memory

  # Storage configuration
  boot_disk = optional(object({
    datastore_id = optional(string, "local-lvm")
    interface    = optional(string, "virtio0")  # Changed from scsi0 to eliminate Proxmox warnings
    size         = optional(number, 32)      # Size in GB
    file_format  = optional(string, "raw")
    iothread     = optional(bool, true)
    ssd          = optional(bool, false)
    discard      = optional(string, "ignore")
  }), {})

  # Network configuration
  network_interfaces = optional(list(object({
    bridge   = optional(string, "vmbr0")
    model    = optional(string, "virtio")
    vlan_id  = optional(number)
    firewall = optional(bool, false)
  })), [{ bridge = "vmbr0" }])

  # Cloud-init configuration
  ip_config = optional(object({
    ipv4_address = optional(string)          # e.g., "192.168.1.100/24"
    ipv4_gateway = optional(string)          # e.g., "192.168.1.1"
  }), {})

  user_account = {
    username = string                        # Username for cloud-init
    password = string                        # Password (use secure source)
    keys     = list(string)                  # SSH public keys
  }

  # Features
  agent_enabled = optional(bool, true)       # Enable QEMU agent
  protection    = optional(bool, false)      # Protection from deletion
  os_type       = optional(string, "l26")    # OS type for Proxmox
}
```

## Outputs

| Name | Description |
| ------ | ------------- |
| `vm_details` | Complete VM configuration details |
| `vm_ipv4_addresses` | Map of VM names to IPv4 addresses |
| `vm_ipv6_addresses` | Map of VM names to IPv6 addresses |
| `vm_network_interfaces` | VM network interface configurations |

## Examples

See the `examples/` directory for complete working examples:

- `examples/basic-vm/` - Simple single VM setup
- `examples/multi-vm/` - Multiple VMs with different configurations
- `examples/advanced/` - Advanced features and configurations

## Requirements

- Terraform >= 1.12.2
- Proxmox VE >= 7.0
- bpg/proxmox provider ~> 0.79

## Security Considerations

- Store sensitive variables (passwords, SSH keys) in secure parameter stores
- Use strong passwords for user accounts
- Enable firewall where appropriate
- Regularly update VM templates and base images
- Implement proper network segmentation

## Troubleshooting

### Common Issues

1. **VM ID conflicts**: Ensure VM IDs are unique across the cluster
2. **Storage issues**: Verify datastore exists and has sufficient space
3. **Network problems**: Check bridge and VLAN configurations
4. **Cloud-init failures**: Verify user account and SSH key configurations

### Debug Commands

```bash
# Check VM status
qm status <vm_id>

# View VM configuration
qm config <vm_id>

# Monitor VM console
qm monitor <vm_id>
```
