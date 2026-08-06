# ==============================================================================
# SECRET VARIABLES - injected from OpenBao as PKR_VAR_* environment variables
# ==============================================================================
# Same convention as packer/variables.pkr.hcl: build.sh reads each field from
# OpenBao and exports it as PKR_VAR_<name>, which Packer maps to variable <name>.
# Nothing is read from a -var-file, so no secret ever lands on disk.
# ==============================================================================

variable "PROXMOX_VE_ENDPOINT" {
  type        = string
  description = "Proxmox API endpoint (without /api2/json)"
  sensitive   = false
}

variable "PKR_PVE_USERNAME" {
  type        = string
  description = "Proxmox username with token ID, in the form user@realm!tokenid"
  sensitive   = false
}

variable "PROXMOX_TOKEN" {
  type        = string
  description = "Proxmox API token secret"
  sensitive   = true
}

variable "PROXMOX_VE_NODE" {
  type        = string
  description = "Proxmox node to build the templates on. Templates are node-local unless the storage is shared, so this must be the node the VDI guests are cloned onto."
  sensitive   = false
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
