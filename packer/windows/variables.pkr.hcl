# ==============================================================================
# SECRET VARIABLES - injected from OpenBao as PKR_VAR_* environment variables
# ==============================================================================
# scripts/build-windows-templates.sh reads each field from OpenBao and exports it
# as PKR_VAR_<name>, which Packer maps to variable <name>. Nothing is read from a
# -var-file, so no secret ever lands on disk.
#
# The names below match the fields that actually exist at
# secret/infrastructure/proxmox. Do not add PROXMOX_VE_USERNAME or
# PROXMOX_VE_NODE: neither is stored there, whatever the docs may say. The
# username is carried inside PROXMOX_VE_API_TOKEN, and the node to build on is a
# build parameter rather than a credential (see proxmox_node below).
# ==============================================================================

variable "PROXMOX_VE_ENDPOINT" {
  type        = string
  description = "Proxmox API endpoint (without /api2/json)"
  sensitive   = false
}

variable "PROXMOX_VE_API_TOKEN" {
  type        = string
  description = "Proxmox API token in the full `user@realm!tokenid=secret` form. Split on the first `=` into the builder's username and token, so the single stored field covers both."
  sensitive   = true
}

variable "PROXMOX_VE_INSECURE" {
  type        = string
  description = "Skip TLS verification"
  default     = "false"
  sensitive   = false
}

variable "WINDOWS_ADMIN_PASSWORD" {
  type        = string
  description = "Local Administrator password baked into both answer files. Packer authenticates over WinRM with it during the build, and the OOBE answer file re-establishes it on every clone."
  sensitive   = true
}

# ==============================================================================
# NON-SECRET BUILD PARAMETERS
# ==============================================================================

variable "proxmox_node" {
  type        = string
  description = "Proxmox node to build the templates on. Templates are node-local unless the storage is shared, so this must be the node the VDI guests are cloned onto."
}

variable "iso_storage_pool" {
  type        = string
  description = "Datastore that already holds the Windows and virtio install ISOs, and where Packer stages the generated answer ISO"
  default     = "local"
}

variable "vm_storage_pool" {
  type        = string
  description = "Datastore for the template's disk, EFI vars and TPM state"
  default     = "local-zfs"
}

variable "bridge" {
  type        = string
  description = "Network bridge for the build VM"
  default     = "vmbr0"
}

variable "vlan_tag" {
  type        = string
  description = "VLAN tag for the build VM. Must be a VLAN Packer can reach over WinRM from wherever the build runs."
  default     = "90"
}
