# VM variables: generic VM definitions, SSH keys, and cloud-init configuration

variable "vms" {
  description = "Map of VMs to create"
  type = map(object({
    vm_id       = number
    name        = string
    description = optional(string)
    tags        = optional(list(string), ["terraform"])
    pool_id     = optional(string)

    # Service VLAN name (required). Selects the guest's subnet + 802.1Q tag:
    # IP = cidrhost(network_cidrs[vlan], vm_id), NIC vlan_id = vlan_ids[vlan].
    # Must be a key in both var.network_cidrs and var.vlan_ids.
    vlan = string

    # Node placement (optional). When unset, main.tf defaults to var.proxmox_node
    # (the primary node). Set to "proxmox-2"/"proxmox-3" to place a VM on another cluster node.
    node_name = optional(string)

    # DHCP/DNS-first addressing (optional), mirroring containers. dhcp = true
    # means no vm_id-derived IP — the lease provides the address and the guest is
    # reached by {name}.{domain}; this is what lets a VM carry a 6-7-digit
    # positional VMID (which would overflow the /24 host space). The lease is the
    # only authority for the address: nothing reserves it, and the gateway answers
    # DNS for its own lease-table clients. See the extended rationale on the
    # containers `dhcp` field in variables-containers.tf.
    dhcp = optional(bool, false)

    # Resource configuration
    cpu_cores        = optional(number, 4)
    cpu_type         = optional(string, "x86-64-v2-AES")
    memory_dedicated = optional(number, 2048)
    memory_floating  = optional(number)

    # Storage configuration
    boot_disk = optional(object({
      datastore_id = optional(string, "local-lvm")
      interface    = optional(string, "scsi0")
      size         = optional(number, 64)
      file_format  = optional(string, "raw")
      iothread     = optional(bool, true)
      ssd          = optional(bool, false)
      discard      = optional(string, "ignore")
    }), {})

    additional_disks = optional(list(object({
      datastore_id = optional(string, "local-zfs")
      interface    = string
      size         = number
      file_format  = optional(string, "raw")
      iothread     = optional(bool, true)
      ssd          = optional(bool, false)
      discard      = optional(string, "ignore")
    })), [])

    # Network configuration
    network_interfaces = optional(list(object({
      bridge   = optional(string, "vmbr0")
      model    = optional(string, "virtio")
      vlan_id  = optional(number)
      firewall = optional(bool, false)
    })), [{ bridge = "vmbr0" }])

    # Initialization
    ip_config = optional(object({
      ipv4_address = optional(string)
      ipv4_gateway = optional(string)
    }), {})

    # Template cloning
    cdrom_file_id = optional(string)
    clone_template = optional(object({
      template_id = number
    }))

    # User account configuration
    user_account = optional(object({
      username = string
      password = string
      keys     = list(string)
      }), {
      username = "debian"
      password = "" # Must be set in terraform.tfvars - do not use default passwords
      keys     = []
    })

    # Display
    vga_type = optional(string, "std")

    # Features
    agent_enabled = optional(bool, true)
    protection    = optional(bool, false)
    os_type       = optional(string, "l26")

    # Cloud-init configuration
    cloud_init_user_data = optional(string)
  }))
  default = {}

  validation {
    condition = alltrue([
      for k, v in var.vms : v.vm_id >= 100 && v.vm_id <= 999999999
    ])
    error_message = "VM IDs must be between 100 and 999999999."
  }

  validation {
    condition = alltrue([
      for k, v in var.vms : v.cpu_cores >= 1 && v.cpu_cores <= 32
    ])
    error_message = "CPU cores must be between 1 and 32."
  }

  validation {
    condition = alltrue([
      for k, v in var.vms : v.memory_dedicated >= 256 && v.memory_dedicated <= 65536
    ])
    error_message = "Memory must be between 256 MB and 64 GB."
  }

  validation {
    condition = alltrue([
      for k, v in var.vms : contains(["std", "cirrus", "vmware", "qxl"], v.vga_type)
    ])
    error_message = "The vga_type for each VM must be one of: std, cirrus, vmware, qxl."
  }
}

# SSH Key Configuration for VMs
variable "vm_ssh_public_key" {
  description = "SSH public key content for VM authentication"
  type        = string
  validation {
    condition     = can(regex("^(ssh-|ecdsa-)", trimspace(var.vm_ssh_public_key)))
    error_message = "SSH public key must be OpenSSH public-key content."
  }
}

# Cloud-init configuration
variable "ansible_cloud_init_file" {
  description = "Path to the cloud-init configuration file for Ansible server"
  type        = string
  default     = "cloud-init/ansible-server-example.yml"
  validation {
    condition     = can(regex("(^|/)cloud-init/.*\\.ya?ml$", var.ansible_cloud_init_file))
    error_message = "Cloud-init file must be in cloud-init/ directory and have .yml or .yaml extension."
  }
}
