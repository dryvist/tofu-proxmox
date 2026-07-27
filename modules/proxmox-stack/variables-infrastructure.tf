# Infrastructure variables: environment identity and Proxmox host connectivity

variable "domain" {
  description = "Internal domain for FQDN resolution (e.g., example.com)"
  type        = string
  default     = ""
}

variable "environment" {
  description = "Environment name for resource tagging and organization"
  type        = string
  default     = "homelab"
}

variable "proxmox_node" {
  description = "The name of the Proxmox node to deploy resources on"
  type        = string
  default     = "proxmox-1"
}

variable "proxmox_ssh_username" {
  description = "The SSH username for connecting to the Proxmox node (for cloud-init, etc.)"
  type        = string
  default     = "root@pam"
  ephemeral   = true
}

variable "proxmox_ssh_private_key" {
  description = "Ephemeral SSH private key content for connecting to the Proxmox node"
  type        = string
  sensitive   = true
  ephemeral   = true
  validation {
    condition     = can(regex("^-----BEGIN", trimspace(var.proxmox_ssh_private_key)))
    error_message = "SSH private key must be PEM/OpenSSH private-key content."
  }
}

variable "proxmox_ssh_host" {
  description = "Hostname or IP for SSH access to the Proxmox node. Used by the acme-certificate module's null_resource provisioner to deliver issued certs to LXCs/VMs. Sourced from PROXMOX_VE_HOSTNAME via OpenBao/tofu."
  type        = string
  default     = ""
  ephemeral   = true
}

variable "inventory_bucket" {
  description = "RustFS bucket receiving the published Ansible inventory"
  type        = string
  default     = "iac-inventory"
}

variable "inventory_key" {
  description = "RustFS object key receiving the published Ansible inventory"
  type        = string
  default     = "ansible_inventory.json"
}

# Proxmox cluster nodes. Keyed by Proxmox node_name (e.g. "proxmox-1", "proxmox-2", "proxmox-3").
# Non-secret identity only — real management/BMC IPs live in private RustFS deployment object
# (see the rack_server_cluster module). A node with commissioned = false is
# declared but not yet installed: no workloads are placed on it and its
# node_storage is not applied until it is brought online.
# See deployment.json.example for a full example with multiple nodes.
variable "nodes" {
  description = "Proxmox cluster node inventory (non-secret identity), surfaced to ansible-proxmox via ansible_inventory."
  type = map(object({
    role         = string               # role label: node-1 | node-2 | node-3
    hardware     = optional(string)     # e.g. amd-desktop, dell-r410, dell-r710
    commissioned = optional(bool, true) # false = declared but not yet installed
    # Distinct from commissioned: an already-installed node can still be
    # temporarily ineligible for per-node ("DaemonSet-style") service
    # placement, e.g. mid storage-rebuild. Gates the root main.tf
    # per-node-service expansion (traefik_node_service_containers and future
    # services built on the same pattern); does not affect anything else a
    # commissioned node already runs.
    services_enabled = optional(bool, true)
  }))
  default = {}
}
