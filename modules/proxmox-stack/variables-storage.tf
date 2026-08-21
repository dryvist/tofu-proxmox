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

# Host-level services (ZFS datasets, Samba, etc.) — not managed by Terraform directly,
# but documented here so ansible-proxmox can consume them via ansible_inventory output.
variable "host_services" {
  description = "Host-level services config (ZFS datasets, Samba shares) for ansible-proxmox consumption"
  type = object({
    nas = optional(object({
      zfs_dataset    = string
      zfs_quota      = string
      mount_point    = string
      smb_share_name = string
      directories    = list(string)
      group_name     = optional(string)
      managed_users = optional(list(object({
        name                = string
        unix_groups         = optional(list(string))
        shell               = optional(string)
        create_home         = optional(bool)
        password_secret_env = string
      })))
      shares = optional(list(object({
        name           = string
        path           = string
        valid_users    = string
        browsable      = optional(bool)
        read_only      = optional(bool)
        force_group    = optional(string)
        create_mask    = optional(string)
        directory_mask = optional(string)
        comment        = optional(string)
        # macOS Time Machine target (consumed by the nas_storage vfs_fruit role).
        time_machine          = optional(bool)
        time_machine_max_size = optional(string)
      })))
      description = optional(string)
    }))
  })
  default = {}
}

# Per-node ZFS storage DECLARATION (not created by Terraform).
# zpool/zfs creation is an OS-level operation the Proxmox API cannot perform, so
# ansible-proxmox consumes this map (via the ansible_inventory output) to create
# pools, datasets, and quotas and to register them with Proxmox. Terraform only
# references the resulting datastore_id on VM/container disks.
#   - register = true  -> ansible-proxmox runs `pvesm add zfspool` (node-scoped)
#   - a node marked commissioned = false should keep register = false until live
variable "node_storage" {
  description = "Per-node ZFS pools/datasets/quotas for ansible-proxmox to provision; Terraform consumes the datastore by id."
  type = map(object({
    # ZFS kernel module parameters for this node, rendered by ansible-proxmox to
    # /etc/modprobe.d/zfs.conf. These are LOAD-TIME settings: a runtime write to
    # /sys/module/zfs/parameters/ reverts on reboot, so anything tuned live must
    # be declared here or it is silently lost at the next boot.
    module_params = optional(map(string), {})
    # Node-level Samba service configuration. Only the SERVICE settings live
    # here; each share is declared on the dataset it serves (see `smb` below),
    # so a node with no shared dataset needs none of this.
    smb = optional(object({
      group_name = optional(string, "nas")
      workgroup  = optional(string, "WORKGROUP")
      # macOS Finder/Time Machine integration (vfs_fruit). Harmless for non-Mac.
      macos_optimized = optional(bool, true)
      managed_users = optional(list(object({
        name                = string
        unix_groups         = optional(list(string))
        shell               = optional(string)
        create_home         = optional(bool)
        password_secret_env = string
      })), [])
    }))
    pools = map(object({
      type = optional(string, "zfspool")
      raid = optional(string) # raidz1, raidz2, mirror (informational; see topology)
      # Physical shape of the pool. Device by-id lists are deliberately NOT here
      # (they are hardware-specific and destructive to act on - see
      # zfs_pools_devices in the ansible role), but the SHAPE is reproducible and
      # belongs in code: it is what makes "build an identical array on new
      # hardware" possible. ansible-proxmox ASSERTS the live pool matches this
      # and fails the converge on drift. ashift is IMMUTABLE after pool creation,
      # so a mismatch there means the pool was built wrong and must be rebuilt.
      topology = optional(object({
        type   = string               # raidz1 | raidz2 | raidz3 | mirror | draid
        width  = number               # number of member devices in the vdev
        ashift = optional(number, 12) # 12 = 4K sectors; correct for 512e drives
      }))
      # Pool-LEVEL properties (`zpool set`), distinct from per-dataset
      # `properties` below (`zfs set`). e.g. autotrim, failmode.
      pool_properties = optional(map(string), {})
      # protected pools must never be auto-destroyed; ansible-proxmox enforces
      # zfs hold / readonly / snapshot retention (storage-safety, design pending).
      protected = optional(bool, true)
      register  = optional(bool, true) # register as PVE storage via pvesm
      content   = optional(list(string), ["images", "rootdir"])
      datasets = optional(map(object({
        quota      = optional(string)
        mountpoint = optional(string)
        nfs_export = optional(string)
        # When set, ansible-proxmox registers this dataset as its own Proxmox
        # zfspool storage id (`pvesm add zfspool <pvesm_id> -pool <pool>/<dataset>`),
        # so a VM/LXC disk can target it directly as a first-class datastore_id.
        # A plain `quota` alone does NOT do this — zfspool-backed VM disks land at
        # the pool root, not inside an arbitrary child dataset. Leave unset (null)
        # for datasets that are only bind-mounted or NFS-exported.
        pvesm_id = optional(string)
        # Arbitrary ZFS properties (recordsize, compression, readonly,
        # com.sun:auto-snapshot, …) applied idempotently by ansible-proxmox.
        # Use ZFS canonical forms as strings (e.g. "1M", "zstd", "false").
        properties = optional(map(string), {})
        # Serve this dataset over SMB. The share lives ON the dataset rather than
        # in a separate node-level list, because the map key already identifies
        # both the node and the dataset -- there is nothing left to select and no
        # way for a share to reference a dataset that does not exist.
        smb = optional(object({
          share_name     = string
          comment        = optional(string)
          valid_users    = optional(string)
          browsable      = optional(bool, true)
          read_only      = optional(bool, false)
          force_group    = optional(string)
          create_mask    = optional(string, "0664")
          directory_mask = optional(string, "0775")
          # macOS Time Machine target (vfs_fruit). max_size is REQUIRED when
          # enabled and enforced below: Time Machine grows until the volume is
          # full, so an uncapped share eventually consumes the whole pool.
          time_machine          = optional(bool, false)
          time_machine_max_size = optional(string)
        }))
      })), {})
    }))
  }))
  default = {}

  # A Time Machine share grows until its volume is full. Without a cap one
  # backup target quietly consumes the entire pool and takes every other
  # dataset on it down with it, so the cap is required rather than advised.
  # A variable validation (not a `check` block) -- a failed check only warns
  # and the plan still exits 0, which would leave the guard looking present
  # while doing nothing.
  validation {
    condition = alltrue([
      for node, cfg in var.node_storage : alltrue([
        for pool, p in cfg.pools : alltrue([
          for ds, d in p.datasets :
          d.smb == null || d.smb.time_machine != true ||
          try(length(d.smb.time_machine_max_size), 0) > 0
        ])
      ])
    ])
    error_message = "A dataset with smb.time_machine = true must also set smb.time_machine_max_size; an uncapped Time Machine share grows until the pool is full."
  }

  # Share names are the SMB namespace of one node; two datasets claiming the
  # same name on the same node silently shadow each other in smb.conf.
  validation {
    condition = alltrue([
      for node, cfg in var.node_storage :
      length([
        for s in flatten([
          for pool, p in cfg.pools : [
            for ds, d in p.datasets : d.smb == null ? [] : [d.smb.share_name]
          ]
        ]) : s
        ]) == length(distinct(flatten([
          for pool, p in cfg.pools : [
            for ds, d in p.datasets : d.smb == null ? [] : [d.smb.share_name]
          ]
      ])))
    ])
    error_message = "Each smb.share_name must be unique within a node; duplicate names shadow each other in smb.conf."
  }
}
