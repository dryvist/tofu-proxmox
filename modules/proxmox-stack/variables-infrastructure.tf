# Infrastructure variables: environment identity and Proxmox host connectivity

variable "domain" {
  description = "Internal domain for FQDN resolution (e.g., example.com)"
  type        = string
  default     = ""
}

# Per-VLAN override of `domain`. Every VLAN's UniFi network carries its own DNS
# domain (tofu-unifi's per-network domain_name), and that is what the gateway
# actually answers a DHCP-first guest's FQDN under — `domain` alone is only
# correct for the VLANs whose network domain happens to equal the estate apex.
# Absent here for a VLAN means "use `domain`", so adding a VLAN never requires
# touching this map.
variable "network_domains" {
  description = "Map of VLAN name => DNS domain, for VLANs whose UniFi network domain differs from `domain`. Absent = use `domain`."
  type        = map(string)
  default     = {}
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

variable "desired_state_etag" {
  description = "ETag of the desired-state object this inventory is rendered from. Published into the inventory so a consumer can tell whether the artifact it holds was built from the CURRENT desired state — an apply is the only thing that refreshes it. Empty disables the downstream check rather than failing it, so a store that returns no ETag degrades to today's behaviour."
  type        = string
  default     = ""
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
    # Name this node carries in the inventory system of record, when it differs
    # from the key. Consumers match that system on name alone, so a node whose
    # record was created ahead of a rename needs the record's name published
    # here — otherwise the consumer creates a second record and strands the
    # first. Unset means the two already agree.
    #
    # Declaring it is what makes it survive: this type strips any attribute it
    # does not name, so an undeclared key would vanish between the deployment
    # object and ansible_inventory with no error.
    nautobot_device_name = optional(string)

    # Cluster ROLES this node plays, as opposed to `role` above, which is a
    # per-node label. Consumers that need "the node that does X" resolve it
    # here instead of carrying a node name of their own.
    #
    # This replaces a set of environment variables that named each node by a
    # positional ordinal. That indirection had two failure modes and hit both:
    # a value that drifted resolved to a placeholder and the consuming task
    # silently no-opped, and the ordinals outlived the naming scheme they were
    # derived from. Placement belongs in the desired state, once.
    #
    # `primary` is NOT set here — it is already `proxmox_node` at the top level
    # of the deployment object, and a second declaration of the same fact is a
    # drift source. Known values: "storage" (serves the bulk datasets other
    # nodes pull from).
    cluster_roles = optional(list(string), [])
  }))
  default = {}
}
