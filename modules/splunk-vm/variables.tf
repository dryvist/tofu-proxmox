variable "domain" {
  description = "Internal domain for FQDN resolution (e.g., example.com)"
  type        = string
  default     = ""
}

variable "vm_id" {
  description = "Unique VM ID for the Splunk VM"
  type        = number

  validation {
    condition     = var.vm_id > 0 && var.vm_id < 10000
    error_message = "VM ID must be between 1 and 9999."
  }
}

variable "name" {
  description = "Name of the Splunk VM"
  type        = string

  validation {
    condition     = length(var.name) > 0 && length(var.name) <= 63
    error_message = "VM name must be between 1 and 63 characters."
  }
}

variable "node_name" {
  description = "Proxmox node name where the VM will be created"
  type        = string

  validation {
    condition     = length(var.node_name) > 0
    error_message = "Node name cannot be empty."
  }
}

variable "pool_id" {
  description = "Resource pool ID for the Splunk VM (optional, empty string means no pool)"
  type        = string
  default     = ""
}

variable "ip_address" {
  description = "IPv4 address with CIDR notation for the Splunk VM (e.g., 192.168.1.100/24)"
  type        = string

  validation {
    condition     = can(cidrhost(var.ip_address, 0))
    error_message = "IP address must be a valid IPv4 address in CIDR notation (e.g., 192.168.1.100/24)."
  }
}

variable "gateway" {
  description = "IPv4 gateway address for the Splunk VM"
  type        = string

  validation {
    condition     = can(regex("^([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\\.([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\\.([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\\.([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])$", var.gateway))
    error_message = "Gateway must be a valid IPv4 address (e.g., 192.168.1.1)."
  }
}

variable "template_id" {
  description = "VM ID of the Docker template to clone from (splunk-docker-template)"
  type        = number
  default     = 9200

  validation {
    condition     = var.template_id > 0 && var.template_id < 10000
    error_message = "Template ID must be between 1 and 9999."
  }
}

variable "datastore_id" {
  description = "Datastore ID for VM disk storage"
  type        = string
  default     = "local-zfs"

  validation {
    condition     = length(var.datastore_id) > 0
    error_message = "Datastore ID cannot be empty."
  }
}

variable "snippets_datastore_id" {
  description = "Datastore ID for cloud-init snippets (must support snippets content type)"
  type        = string
  default     = "local"

  validation {
    condition     = length(var.snippets_datastore_id) > 0
    error_message = "Snippets datastore ID cannot be empty."
  }
}

variable "bridge" {
  description = "Network bridge for VM network interface"
  type        = string
  default     = "vmbr0"

  validation {
    condition     = length(var.bridge) > 0
    error_message = "Bridge name cannot be empty."
  }
}

variable "vlan_id" {
  description = "802.1Q VLAN tag for the VM NIC. Null = untagged native VLAN."
  type        = number
  default     = null
}

variable "ssh_public_key" {
  description = "SSH public key content for VM access (optional)"
  type        = string
  default     = ""
  sensitive   = true

  validation {
    condition     = can(regex("^(ssh-rsa |ssh-ed25519 |ecdsa-sha2-|$)", var.ssh_public_key))
    error_message = "SSH public key must be empty or start with a valid SSH key type prefix."
  }
}

variable "boot_disk_size" {
  description = "Size of the boot disk in GB"
  type        = number
  default     = 25

  validation {
    condition     = var.boot_disk_size > 0 && var.boot_disk_size <= 1000
    error_message = "Boot disk size must be between 1 and 1000 GB."
  }
}

variable "data_disk_size" {
  description = "Size of the additional data disk in GB (0 = no additional disk)"
  type        = number
  default     = 200

  validation {
    condition     = var.data_disk_size >= 0 && var.data_disk_size <= 1000
    error_message = "Data disk size must be between 0 and 1000 GB."
  }
}

variable "cpu_cores" {
  description = "Number of CPU cores for the Splunk VM"
  type        = number
  default     = 8 # increased from 6: more indexing pipelines for high-volume ingest

  validation {
    condition     = var.cpu_cores >= 1 && var.cpu_cores <= 32
    error_message = "CPU cores must be between 1 and 32."
  }
}

variable "memory" {
  description = "Memory in MB for the Splunk VM"
  type        = number
  default     = 12288 # increased from 6144: Splunk Enterprise minimum is 12 GB; 6 GB caused OOM kills

  validation {
    condition     = var.memory >= 1024 && var.memory <= 65536
    error_message = "Memory must be between 1024 MB and 65536 MB."
  }
}

variable "startup_delay" {
  description = "Delay in seconds after this VM starts before the next tier starts"
  type        = number
  default     = 10
}

variable "tiered_disks" {
  description = "Additional tiered Splunk data disks (fast-splunk hot/warm, bulk-splunk cold)."
  type = map(object({
    datastore_id = string
    interface    = string
    size         = number
    backup       = optional(bool, false)
    file_format  = optional(string, "raw")
    iothread     = optional(bool, true)
    ssd          = optional(bool, false)
    discard      = optional(string, "ignore")
  }))
  default = {}
}
