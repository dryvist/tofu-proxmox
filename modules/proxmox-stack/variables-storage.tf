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


# NixOS LXC template (see ct_templates.tf). Empty by default: the tarball is a
# nix-ai release asset, and a committed URL would be a guess. Supplied from the
# private desired state alongside the other media coordinates.
variable "nixos_ct_template_url" {
  description = "URL of the NixOS LXC template tarball built by nix-ai. Empty disables the download and, with it, any NixOS guest."
  type        = string
  default     = ""
  validation {
    condition     = var.nixos_ct_template_url == "" || can(regex("^https?://", var.nixos_ct_template_url))
    error_message = "nixos_ct_template_url must start with http:// or https:// -- the provider's download-url API rejects anything else."
  }
}

variable "nixos_ct_template_file_name" {
  description = "vztmpl file name the NixOS template is stored as. Must be the value a guest's ct_template field references."
  type        = string
  default     = "nixos-herdr-lxc.tar.xz"
  validation {
    condition     = endswith(var.nixos_ct_template_file_name, ".tar.xz") || endswith(var.nixos_ct_template_file_name, ".tar.zst") || endswith(var.nixos_ct_template_file_name, ".tar.gz")
    error_message = "nixos_ct_template_file_name must be a tarball -- Proxmox refuses a vztmpl with any other extension."
  }
}

variable "nixos_ct_template_sha256" {
  description = "sha256 of the NixOS LXC template. Pinned so content drift is rejected at download time rather than producing a guest that half-boots."
  type        = string
  default     = ""
  validation {
    condition     = var.nixos_ct_template_sha256 == "" || can(regex("^[0-9a-f]{64}$", var.nixos_ct_template_sha256))
    error_message = "nixos_ct_template_sha256 must be 64 lowercase hex characters."
  }
}
