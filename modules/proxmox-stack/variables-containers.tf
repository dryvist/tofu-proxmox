# Container variables: LXC container definitions and configuration

variable "containers" {
  description = "Map of containers to create"
  type = map(object({
    vm_id       = number
    hostname    = string
    description = optional(string)

    # One-line board subtitle. Not `description`: that carries placement
    # rationale and is far too long for a link.
    summary = optional(string)

    tags    = optional(list(string), ["terraform", "container"])
    pool_id = optional(string)

    # Service VLAN name (required). Selects the guest's subnet + 802.1Q tag:
    # IP = cidrhost(network_cidrs[vlan], vm_id) (unless ip_config.ipv4_address pins a
    # static address, or dhcp = true); NIC vlan_id = vlan_ids[vlan]. Must be a key in
    # network_cidrs; a key ABSENT from vlan_ids yields an UNTAGGED NIC (native VLAN,
    # e.g. mgmt_native).
    vlan = string

    # DNS-first addressing: the guest takes its address by DHCP and is referenced
    # by FQDN everywhere. The default for ordinary guests. Set false ONLY for
    # network and critical guests, which pin ip_config.ipv4_address.
    # See docs/CONTAINER_SCHEMA.md.
    dhcp = optional(bool, false)

    # Node placement. REQUIRED, deliberately: this was `optional(string)` with
    # main.tf falling back to var.proxmox_node, and the fallback was silent — a
    # guest that simply omitted the field landed on the primary node with no
    # signal that a placement decision had been skipped. That is how the primary
    # node accumulated the majority of the estate's containers, including every
    # tier of the log pipeline, without anyone choosing to put them there.
    # Placement is now an explicit declaration; there is no default to inherit.
    node_name = string

    # Resource configuration
    cpu_cores        = optional(number, 2)
    memory_dedicated = optional(number, 512)
    memory_swap      = optional(number)

    # Storage
    root_disk = optional(object({
      datastore_id = optional(string)
      size         = optional(number, 16)
    }), {})

    # Mount points (additional volumes mounted into the container). Omit `size`
    # for a host-directory bind-mount; set it to allocate a managed volume.
    # `backup` defaults to TRUE here, inverting the provider's default.
    # See docs/CONTAINER_SCHEMA.md.
    mount_points = optional(list(object({
      volume = string
      size   = optional(string)
      path   = string
      backup = optional(bool, true)
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

    # Boot ORDER override; lower starts first. Unset keeps the VMID-derived
    # order in modules/proxmox-container/main.tf, so this is a no-op until a
    # guest sets it. See docs/CONTAINER_SCHEMA.md.
    startup_order = optional(number)

    # Bare vztmpl filename on var.datastore_iso; null = the shared Debian
    # template. Pair with os_type = "unmanaged" for NixOS. SET-ONCE:
    # template_file_id is in the container module's ignore_changes, and
    # ct_templates.tf carries the rest.
    ct_template = optional(string)

    # HA opt-in; enrolling also accepts the relocation hazard imports.tf
    # documents. ha_affinity_group keeps members on separate nodes via a
    # proxmox_harule and is meaningful only with ha = true. See ha.tf.
    ha                = optional(bool, false)
    ha_affinity_group = optional(string)

    # The node holding this guest's pvesr replica, and so the ONLY node HA may
    # relocate it to on node loss. Unset = no replica; consumers must read that
    # as "not replicated", never as a default node.
    # See docs/CONTAINER_SCHEMA.md.
    ha_replication_target = optional(string)

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

  # A static guest must actually declare its address. dhcp = false with no
  # ipv4_address falls through to the vm_id-derived cidrhost() branch, which
  # silently produces a wrong (or out-of-range) address for any guest carrying a
  # positional 6-digit VMID. This is the inverse of the rule that used to live
  # here: the old one demanded a hand-picked octet from every LEASED guest, which
  # is exactly backwards — leases need no declaration, static addresses do.
  validation {
    condition = alltrue([
      for k, v in var.containers :
      try(v.ip_config.ipv4_address, null) != null || v.vm_id <= 254
      if !try(v.dhcp, false)
    ])
    error_message = "A static container (dhcp = false) with a positional VMID above 254 must pin ip_config.ipv4_address — the vm_id-derived fallback cannot express it. Static addressing is reserved for network/critical guests; everything else should take dhcp = true and a pool lease."
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

  # hermes-donna is a second Hermes agent instance and deliberately carries NO
  # dedicated firewall map of its own — it relies on the hermes-agent tag's
  # existing container-id filter to pick up the hermes-agent security groups
  # and rules. The same hazard as the ai-runner check above applies: a guest
  # tagged hermes-donna without also carrying hermes-agent would silently
  # match no firewall map at all and come up with no firewall options and no
  # rules, invisible in a plan diff.
  validation {
    condition = alltrue([
      for k, v in var.containers :
      contains(coalesce(try(v.tags, null), []), "hermes-agent")
      if contains(coalesce(try(v.tags, null), []), "hermes-donna")
    ])
    error_message = "Every container tagged 'hermes-donna' must also carry the 'hermes-agent' tag — hermes-donna has no firewall map of its own and relies on hermes_agent_container_ids to pick it up. A missing hermes-agent tag would leave the guest with NO firewall."
  }

  # App-dependency tags on the agent guests. Unlike the two checks above these
  # do not gate a firewall map — they record what the guest's converge installs
  # or calls, including services that live outside the container. That makes
  # them the inventory answer to "which guests have Chromium on them" and
  # "which guests break if the extraction service is down", questions the tag
  # list is the only place to ask.
  #
  # Enforced rather than advisory for the same reason as the firewall tags: an
  # agent guest missing 'chromium' is not a plan diff anyone would notice, and
  # the symptom — an agent that answers about pages it never actually read —
  # surfaces far downstream from the cause.
  validation {
    condition = alltrue([
      for k, v in var.containers : length(setsubtract(
        toset(["chromium", "hindsight-client", "firecrawl-client"]),
        toset(coalesce(try(v.tags, null), [])),
      )) == 0
      if contains(coalesce(try(v.tags, null), []), "hermes-agent")
    ])
    error_message = "Every container tagged 'hermes-agent' must also carry 'chromium', 'hindsight-client' and 'firecrawl-client'. These name the app dependencies the agent converge installs or calls — the browser on the guest, and the memory and extraction services off it. Note the -client suffixes are load-bearing: a bare 'hindsight' or 'firecrawl' tag would put the agent guest into that SERVICE's firewall map and treat it as a server instance."
  }

  # Proxmox stores startup order as a positive integer; 0 and fractions are
  # silently coerced, which would reorder a guest without saying so.
  validation {
    condition = alltrue([
      for name, c in var.containers :
      c.startup_order == null || (c.startup_order >= 1 && floor(c.startup_order) == c.startup_order)
    ])
    error_message = "containers.<name>.startup_order must be a positive whole number (lower starts first), or unset to keep the VMID-derived order."
  }
}
