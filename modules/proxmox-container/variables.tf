variable "containers" {
  description = "Map of containers to create"
  type = map(object({
    vm_id       = number
    node_name   = string
    description = optional(string)
    tags        = optional(list(string), ["terraform", "container"])
    pool_id     = optional(string)

    # Container specific
    hostname         = string
    template_file_id = string
    os_type          = optional(string, "debian")

    # Resource configuration
    cpu_cores        = optional(number, 1)
    memory_dedicated = optional(number, 512)
    memory_swap      = optional(number)

    # Storage
    root_disk = optional(object({
      datastore_id = optional(string)
      size         = optional(number, 8)
    }), {})

    # Mount points
    # `size` is optional: omit it for host-directory bind-mounts (volume is a
    # host path like "/example-pool/media"), set it to allocate a new managed volume.
    # `backup` defaults to true, inverting the provider's default of false —
    # a data mount excluded from backups produces an archive holding only the
    # rootfs, and the backup job still reports success.
    mount_points = optional(list(object({
      volume = string
      size   = optional(string)
      path   = string
      backup = optional(bool, true)
    })), [])

    # Device passthrough (e.g. /dev/net/tun for WireGuard inside an LXC).
    # Each entry maps a host device node into the container. `mode` is a
    # 4-digit octal string (e.g. "0666"). Requires root@pam-capable auth.
    device_passthrough = optional(list(object({
      path       = string
      mode       = optional(string)
      uid        = optional(number)
      gid        = optional(number)
      deny_write = optional(bool)
    })), [])

    # Network
    network_interfaces = optional(list(object({
      name     = optional(string, "eth0")
      bridge   = optional(string, "vmbr0")
      firewall = optional(bool, true)
      vlan_id  = optional(number)
      # Deterministic MAC for DHCP-first guests (set by the root module from
      # local.container_mac). Null for static guests, so the provider keeps
      # auto-generating their MAC and existing containers are not disrupted.
      mac_address = optional(string)
    })), [{ name = "eth0", bridge = "vmbr0", firewall = true }])

    # Initialization
    ip_config = optional(object({
      ipv4_address = optional(string)
      ipv4_gateway = optional(string)
    }), {})

    user_account = optional(object({
      password = optional(string, "")
      keys     = optional(list(string), [])
    }), {})

    # Features
    unprivileged  = optional(bool, false)
    protection    = optional(bool, false)
    start_on_boot = optional(bool, true)

    # Boot ORDER override; lower starts first. Unset keeps the VMID-derived
    # order in modules/proxmox-container/main.tf, so this is a no-op until a
    # guest sets it. See docs/CONTAINER_SCHEMA.md.
    startup_order = optional(number)

    # LXC features (nesting required for Docker-in-LXC)
    features = optional(object({
      nesting = optional(bool, true)
      keyctl  = optional(bool, false)
      fuse    = optional(bool, false)
      mount   = optional(list(string), [])
    }), { nesting = true, keyctl = false, fuse = false, mount = [] })
  }))
  default = {}
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
  description = "Default datastore for container storage (passed from root module)"
  type        = string
  default     = "local-zfs"
}

variable "startup_delay" {
  description = "Delay in seconds after this tier starts before the next tier starts"
  type        = number
  default     = 10
}
