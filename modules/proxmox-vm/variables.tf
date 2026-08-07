variable "vms" {
  description = "Map of VMs to create"
  type = map(object({
    vm_id       = number
    name        = string
    description = optional(string)
    tags        = optional(list(string), ["terraform"])
    pool_id     = optional(string)

    # Node configuration
    node_name = string

    # See the extended rationale on this field in the proxmox-stack VM schema.
    # Short version: the provider forces replacement on a node_name change
    # unless this is true, so a move without it destroys the VM's disks.
    migrate = optional(bool, false)

    # Resource configuration
    cpu_cores = optional(number, 2)
    # cpu_type: "host" for single-node homelab stability (zero CPU emulation overhead)
    # VMs inherit all host CPU features. Not portable across different CPUs.
    cpu_type         = optional(string, "host")
    memory_dedicated = optional(number, 1024)
    memory_floating  = optional(number)

    # Storage configuration
    boot_disk = optional(object({
      datastore_id = optional(string, "local-lvm")
      interface    = optional(string, "scsi0")
      size         = optional(number, 32)
      file_format  = optional(string, "raw")
      iothread     = optional(bool, true)
      ssd          = optional(bool, false)
      discard      = optional(string, "ignore")
    }), {})

    # Additional disks
    additional_disks = optional(list(object({
      datastore_id = string
      interface    = string
      size         = number
      file_format  = optional(string, "raw")
      iothread     = optional(bool, true)
      ssd          = optional(bool, false)
      discard      = optional(string, "ignore")
    })), [])

    # Network configuration
    network_interfaces = optional(list(object({
      bridge      = optional(string, "vmbr0")
      model       = optional(string, "virtio")
      vlan_id     = optional(number)
      firewall    = optional(bool, false)
      mac_address = optional(string)
    })), [{ bridge = "vmbr0" }])

    # Initialization
    ip_config = optional(object({
      ipv4_address = optional(string)
      ipv4_gateway = optional(string)
      ipv6_address = optional(string)
      ipv6_gateway = optional(string)
    }), {})

    # Cloud-init / OS configuration
    cdrom_file_id = optional(string)
    clone_template = optional(object({
      template_id = number
      # false = linked clone (copy-on-write). See the same field in
      # modules/proxmox-stack/variables-vms.tf for the trade-offs.
      full = optional(bool, true)
    }))
    user_account = object({
      username = string
      password = string
      keys     = list(string)
    })

    # Cloud-init user data
    cloud_init_user_data = optional(string)

    # Agent and features
    agent_enabled = optional(bool, true)
    protection    = optional(bool, false)

    # Operating system
    os_type = optional(string, "l26")
    # "seabios" or "ovmf". Windows 11+ requires "ovmf" (UEFI) alongside
    # tpm_state/efi_disk to pass hardware install checks.
    bios = optional(string, "seabios")

    # Display configuration
    vga_type = optional(string, "std")

    # Startup configuration
    on_boot = optional(bool, true)
    started = optional(bool, true)

    # Windows features
    tpm_state = optional(object({
      version      = optional(string, "v2.0")
      datastore_id = string
    }))
    efi_disk = optional(object({
      type              = optional(string, "4m")
      pre_enrolled_keys = optional(bool, false)
      datastore_id      = string
    }))

  }))
  default = {}

  # VGA type is validated against allowed types
  # Allowed values: std, cirrus, vmware, qxl
}

variable "domain" {
  description = "Internal domain for FQDN resolution (e.g., example.com)"
  type        = string
  default     = ""
}

variable "environment" {
  description = "Environment name for resource tagging"
  type        = string
  default     = "homelab"
}

variable "default_datastore" {
  description = "Default datastore for VM storage"
  type        = string
  default     = "local-zfs"
}

# Note: BPG provider authentication is read from PROXMOX_VE_* environment variables
# These module variables are not needed for provider auth

variable "proxmox_ssh_username" {
  description = "The SSH username for connecting to the Proxmox node"
  type        = string
  default     = "root@pam"
  ephemeral   = true
}

variable "proxmox_ssh_private_key" {
  description = "Ephemeral SSH private key content for connecting to the Proxmox node"
  type        = string
  sensitive   = true
  ephemeral   = true
}

variable "startup_delay" {
  description = "Delay in seconds after this tier starts before the next tier starts"
  type        = number
  default     = 10
}
