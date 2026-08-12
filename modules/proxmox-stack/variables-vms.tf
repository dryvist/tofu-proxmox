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

    # Node placement. REQUIRED — see the same field on var.containers for why the
    # silent fallback to var.proxmox_node was removed.
    node_name = string

    # Whether a change to node_name migrates the VM or rebuilds it. The provider
    # decides this in CustomizeDiff, not in the schema: a node_name change forces
    # replacement UNLESS migrate is true. So moving a VM between nodes without
    # this set destroys its disks and reclones from the template — measured on a
    # 150 GB guest, which planned "must be replaced" until migrate was declared.
    # Left false by default: replacement is the safe outcome for a guest whose
    # disks are disposable, and an accidental migration of a large VM is not.
    migrate = optional(bool, false)

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
      # full = false makes a linked clone: copy-on-write off the template's
      # snapshot instead of copying its disk up front. A full clone of a
      # Windows template costs 9-12 GB each and can exhaust a boot pool; a
      # linked one starts at ~0 and grows only with what the guest writes.
      # The trade is that the template cannot be deleted while a linked clone
      # exists, and both must live on the same storage. Defaults to the
      # provider's own default (true) so nothing changes unless asked.
      full = optional(bool, true)
      # The node holding the TEMPLATE, when it is not the node the guest is
      # being built on. Templates are node-local unless their storage is
      # shared, so without this the provider looks for the template on the
      # target node and Proxmox answers with a bare HTTP 500, "unable to find
      # configuration file for VM <id> on node '<target>'" — which reads as a
      # broken template rather than a missing source node. Omit when the
      # template already lives on the target.
      node_name = optional(string)
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

    # Startup behaviour. Both default true, matching the provider.
    #   on_boot - start the guest when the NODE boots.
    #   started - the run state terraform asserts at CREATE time.
    # They are independent: on_boot alone still lets an apply power a guest on.
    # A guest the operator alone may start needs both false (the provider's own
    # documented pattern for a VM that is never started automatically).
    on_boot = optional(bool, true)
    started = optional(bool, true)

    # Features
    agent_enabled = optional(bool, true)
    protection    = optional(bool, false)
    os_type       = optional(string, "l26")
    # "seabios" or "ovmf". Windows 11+ requires "ovmf" (UEFI) alongside
    # tpm_state/efi_disk to pass hardware install checks.
    bios = optional(string, "seabios")

    # Ansible connection method published in ansible_inventory (inventory_publish.tf).
    # "ssh" (default) or "winrm" for Windows guests.
    ansible_connection = optional(string, "ssh")

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
