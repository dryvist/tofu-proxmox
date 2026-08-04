# Splunk variables: VM sizing, identity, and SSH access for the Splunk deployment

variable "splunk_vm_id" {
  description = "VM ID for the Splunk VM. The real VM ID is the single source of truth in deployment.json (injected by tofu); this default is a non-production placeholder (kept a valid /24 host octet so the derived siem IP resolves) so tests and standalone plans resolve without redeclaring it."
  type        = number
  default     = 99
  validation {
    condition     = var.splunk_vm_id > 0 && var.splunk_vm_id < 10000
    error_message = "Splunk VM ID must be between 1 and 9999."
  }
}

variable "splunk_vm_name" {
  description = "Name of the Splunk VM"
  type        = string
  default     = "splunk-vm"
  validation {
    condition     = length(var.splunk_vm_name) > 0 && length(var.splunk_vm_name) <= 63
    error_message = "Splunk VM name must be between 1 and 63 characters."
  }
}

variable "splunk_vm_pool_id" {
  description = "Resource pool ID for the Splunk VM (optional)"
  type        = string
  default     = ""
}

variable "splunk_boot_disk_size" {
  description = "Size of Splunk VM boot disk in GB"
  type        = number
  default     = 25

  validation {
    condition     = var.splunk_boot_disk_size > 0 && var.splunk_boot_disk_size <= 1000
    error_message = "Splunk boot disk size must be between 1 and 1000 GB."
  }
}

variable "splunk_data_disk_size" {
  description = "Size of Splunk VM additional data disk in GB (0 = no additional disk)"
  type        = number
  default     = 200

  validation {
    condition     = var.splunk_data_disk_size >= 0 && var.splunk_data_disk_size <= 1000
    error_message = "Splunk data disk size must be between 0 and 1000 GB."
  }
}

variable "splunk_fast_disk_size" {
  description = "Size of the fast-splunk tier disk in GB (hot + warm buckets, on the fast/mirror pool)"
  type        = number
  default     = 1024

  validation {
    condition     = var.splunk_fast_disk_size > 0 && var.splunk_fast_disk_size <= 4096
    error_message = "Splunk fast-splunk disk size must be between 1 and 4096 GB."
  }
}

variable "splunk_bulk_disk_size" {
  description = "Size of the bulk-splunk tier disk in GB (cold buckets, on the non-RAID cold pool; not backed up by design)"
  type        = number
  default     = 2048

  validation {
    condition     = var.splunk_bulk_disk_size > 0 && var.splunk_bulk_disk_size <= 8192
    error_message = "Splunk bulk-splunk disk size must be between 1 and 8192 GB."
  }
}

variable "splunk_node_name" {
  description = "Proxmox node the Splunk VM is placed on. Previously hardwired to var.proxmox_node, which made the VM unplaceable anywhere but the primary node. The root module falls back to proxmox_node when the deployment object names no node, so this stays a no-op until one does — a fallback covering one explicitly-named guest, not the whole-class fallback that var.containers.node_name used to carry. This default is the same non-production placeholder var.proxmox_node uses, so tests and standalone plans resolve without redeclaring it."
  type        = string
  default     = "proxmox-1"
}

variable "splunk_cpu_type" {
  description = "QEMU CPU model for the Splunk VM. See modules/splunk-vm/variables.tf — \"host\" blocks cross-vendor migration."
  type        = string
  default     = "host"
}

variable "splunk_migrate" {
  description = "Whether a splunk_node_name change migrates the VM or destroys and recreates it."
  type        = bool
  default     = false
}

variable "splunk_cpu_cores" {
  description = "Number of CPU cores for the Splunk VM"
  type        = number
  default     = 8 # increased from 6: more indexing pipelines for high-volume ingest

  validation {
    condition     = var.splunk_cpu_cores >= 1 && var.splunk_cpu_cores <= 32
    error_message = "CPU cores must be between 1 and 32."
  }
}

variable "splunk_memory" {
  description = "Memory in MB for the Splunk VM"
  type        = number
  default     = 12288 # increased from 6144: Splunk Enterprise minimum is 12 GB; 6 GB caused OOM kills

  validation {
    condition     = var.splunk_memory >= 1024 && var.splunk_memory <= 65536
    error_message = "Memory must be between 1024 MB and 65536 MB."
  }
}

variable "ssh_public_key" {
  description = "SSH public key content for Splunk VM access (optional)"
  type        = string
  default     = ""
  sensitive   = true
  validation {
    condition     = can(regex("^(ssh-rsa |ssh-ed25519 |ecdsa-sha2-|$)", var.ssh_public_key))
    error_message = "SSH public key must be empty or start with a valid SSH key type prefix."
  }
}
