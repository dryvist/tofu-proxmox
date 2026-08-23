# Storage variables: datastores, templates, ISOs, and host-level services

variable "datastore_default" {
  description = "Default datastore for VM disks and container volumes"
  type        = string
  default     = "local-zfs"
}

variable "datastore_iso" {
  description = "Datastore for ISO images and container templates"
  type        = string
  default     = "local"
}

# A whole base URL rather than a host composed from var.domain: the scheme,
# name and port of the object store are all environment-specific, so the value
# is supplied from the private desired-state object the same way datastore_iso
# is. The committed default is a non-functional placeholder.
variable "iso_base_url" {
  description = "Base URL of the read-only object prefix holding install media (no trailing slash). Supplied from the private desired state; the committed default is a non-functional placeholder."
  type        = string
  default     = "https://s3.example.com/isos"
  validation {
    condition     = can(regex("^https?://", var.iso_base_url))
    error_message = "iso_base_url must start with http:// or https:// -- the provider's download-url API rejects anything else."
  }
  validation {
    condition     = !endswith(var.iso_base_url, "/")
    error_message = "iso_base_url must not end with a slash; the ISO resources append their own path separator."
  }
}

variable "datastore_id" {
  description = "Datastore ID for Splunk VM disk storage"
  type        = string
  default     = "local-zfs"
  validation {
    condition     = length(var.datastore_id) > 0
    error_message = "Datastore ID cannot be empty."
  }
}

variable "datastores" {
  description = "Map of additional datastores to create beyond default local storage"
  type = map(object({
    type    = string # "dir", "nfs", etc.
    path    = optional(string)
    content = optional(list(string), ["images", "vztmpl", "iso", "backup"])
    shared  = optional(bool, false)
    nodes   = optional(list(string))
    # NFS specific
    server  = optional(string)
    export  = optional(string)
    options = optional(string)
  }))
  default = {}
}

# Template and ISO configuration
variable "proxmox_ct_template_debian" {
  description = "The name of the Debian container template to use for containers"
  type        = string
  default     = "debian-13-standard_13.1-2_amd64.tar.zst"
}

variable "proxmox_iso_debian" {
  description = "The name of the Debian ISO file to use for VMs"
  type        = string
  default     = "debian-13.2.0-amd64-netinst.iso"
}

variable "template_id" {
  description = "VM ID of the Packer-built Splunk Docker template to clone from (default: splunk-docker-template ID 9201)"
  type        = number
  default     = 9201
  validation {
    condition     = var.template_id > 0 && var.template_id < 10000
    error_message = "Template ID must be between 1 and 9999."
  }
}

