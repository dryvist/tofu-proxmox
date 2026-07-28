# Container variables: LXC container definitions and configuration

variable "containers" {
  description = "Map of containers to create"
  type = map(object({
    vm_id       = number
    hostname    = string
    description = optional(string)
    tags        = optional(list(string), ["terraform", "container"])
    pool_id     = optional(string)

    # Service VLAN name (required). Selects the guest's subnet + 802.1Q tag:
    # IP = cidrhost(network_cidrs[vlan], vm_id) (unless ip_config.ipv4_address pins a
    # static address, or dhcp = true); NIC vlan_id = vlan_ids[vlan]. Must be a key in
    # network_cidrs; a key ABSENT from vlan_ids yields an UNTAGGED NIC (native VLAN,
    # e.g. mgmt_native).
    vlan = string

    # DNS-first addressing (see docs vmid-network-tiers). When true the guest takes
    # its address by DHCP and is referenced by FQDN ({hostname}.{domain}) everywhere
    # — no vm_id-derived IP is computed, so the guest may carry a 6-digit positional
    # VMID that the /24 cidrhost math could not express. DNS owns the address; the
    # guest stays reachable across re-IP/rebuild. Defaults false (legacy static IP).
    dhcp = optional(bool, false)

    # DHCP-reservation host octet for dhcp guests. UniFi pins the guest's
    # deterministic MAC (local.container_mac) to cidrhost(network_cidrs[vlan],
    # reserved_host), and the DNS A record points at that same address. Decoupled
    # from the 6-digit positional vm_id so the reserved address is a real host in the
    # guest's VLAN /24. Required whenever dhcp = true (see the validation below).
    reserved_host = optional(number)

    # Node placement (optional). When unset, main.tf defaults to var.proxmox_node
    # (the primary node). Set to "proxmox-2"/"proxmox-3" to place an LXC on another cluster node.
    node_name = optional(string)

    # Resource configuration
    cpu_cores        = optional(number, 2)
    memory_dedicated = optional(number, 512)
    memory_swap      = optional(number)

    # Storage
    root_disk = optional(object({
      datastore_id = optional(string)
      size         = optional(number, 16)
    }), {})

    # Mount points (additional volumes mounted into the container)
    # Omit `size` for host-directory bind-mounts (volume = host path such as
    # "/example-pool/media"); set it to allocate a new managed volume.
    mount_points = optional(list(object({
      volume = string
      size   = optional(string)
      path   = string
    })), [])

    # Host device nodes mapped into the container. Used by download-vpn for
    # /dev/net/tun so WireGuard can create the wg0 interface inside the LXC.
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
    })), [{ name = "eth0", bridge = "vmbr0", firewall = true }])

    # Initialization
    ip_config = optional(object({
      ipv4_address = optional(string)
      ipv4_gateway = optional(string)
    }), {})

    # User account configuration
    user_account = optional(object({
      username = string
      password = string
      keys     = list(string)
    }))

    unprivileged  = optional(bool, false)
    protection    = optional(bool, false)
    os_type       = optional(string, "debian")
    start_on_boot = optional(bool, true)

    # LXC features (set nesting=true for Docker-in-LXC on unprivileged containers;
    # privileged containers run Docker without features — requires root@pam to set any flag)
    features = optional(object({
      nesting = optional(bool, false)
      keyctl  = optional(bool, false)
      fuse    = optional(bool, false)
      mount   = optional(list(string), [])
    }), { nesting = false, keyctl = false, fuse = false, mount = [] })
  }))
  default = {}

  validation {
    condition = alltrue([
      for k, v in var.containers : v.vm_id >= 100 && v.vm_id <= 999999999
    ])
    error_message = "Container IDs must be between 100 and 999999999."
  }

  validation {
    condition = alltrue([
      for k, v in var.containers : v.cpu_cores >= 1 && v.cpu_cores <= 32
    ])
    error_message = "Container CPU cores must be between 1 and 32."
  }

  validation {
    condition = alltrue([
      for k, v in var.containers : v.memory_dedicated >= 64 && v.memory_dedicated <= 65536
    ])
    error_message = "Container memory must be between 64 MB and 64 GB."
  }

  validation {
    condition = alltrue([
      for k, v in var.containers : try(v.reserved_host, null) != null if try(v.dhcp, false)
    ])
    error_message = "Every dhcp = true container must set reserved_host: it is the host octet UniFi pins the deterministic MAC to (DHCP reservation) and the DNS A record resolves to."
  }

  # An AI runner/agent guest runs a coding agent in permission-skipping mode, so
  # the container firewall is the ONLY safety control. Its egress profile is
  # selected by tag, and the firewall module's per-profile maps are built by
  # filtering on that tag — which means a MISSING or MISSPELLED profile tag
  # silently matches no map at all and the guest comes up with no firewall
  # options and no rules. That failure mode is invisible in a plan diff, so it
  # is a hard error here rather than an advisory check: every ai-runner-tagged
  # guest must carry exactly one known profile tag.
  validation {
    condition = alltrue([
      for k, v in var.containers : length(setintersection(
        toset(coalesce(try(v.tags, null), [])),
        toset(["ai-github", "ai-terrakube", "ai-full-net", "ai-proxied"]),
      )) == 1
      if contains(coalesce(try(v.tags, null), []), "ai-runner")
    ])
    error_message = "Every container tagged 'ai-runner' must carry exactly one egress-profile tag from: ai-github, ai-terrakube, ai-full-net, ai-proxied. A missing or misspelled profile tag would leave the agent guest with NO firewall; two would attach conflicting rule sets."
  }
}
