# Per-node ZFS storage declaration. Split out of variables-storage.tf: that
# file reached the shared 12 KB per-file gate, and this is its largest single
# variable by a wide margin.

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
      # A login name is a credential, not a label: it is half of what an
      # attacker needs and it is not rotatable once published. So the ACCOUNT
      # is named here by its ROLE, and both the username and the password are
      # read from the node's NAS secret at converge time as
      # <secret_prefix>_username and <secret_prefix>_password.
      #
      # This is why there is no `name` field. An earlier revision had one, and
      # it put the login name into the desired-state object, into the password
      # secret's own FIELD name, and into every converge log line -- three
      # publications of a value that can never be un-published.
      managed_users = optional(list(object({
        secret_prefix = string # e.g. "smb_service_account", "smb_user"
        unix_groups   = optional(list(string))
        shell         = optional(string)
        create_home   = optional(bool)
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
        # Capacity of ONE member device, e.g. "5.46T". Width alone does not give
        # capacity, and without capacity a declared quota cannot be checked
        # against anything -- which is how a pool ends up carrying quotas that
        # sum past what it can hold, or a quota sized for a pool it outgrew.
        # Set it and the validation below becomes live for this pool; leave it
        # unset and that pool is simply not checked.
        #
        # Use the size ZFS reports per member (`zpool list -v`), not the vendor's
        # marketing capacity: a "6 TB" disk is 5.46 TiB, and using 6T here would
        # over-state the pool by 10% and defeat the guard it feeds.
        device_size = optional(string)
      }))
      # Pool-LEVEL properties (`zpool set`), distinct from per-dataset
      # `properties` below (`zfs set`). e.g. autotrim, failmode.
      pool_properties = optional(map(string), {})
      # protected pools must never be auto-destroyed; ansible-proxmox enforces
      # zfs hold / readonly / snapshot retention (storage-safety, design pending).
      protected = optional(bool, true)
      register  = optional(bool, true) # register as PVE storage via pvesm
      content   = optional(list(string), ["images", "rootdir"])
      # Thin-provision disks created on this pool's PVE storage. Without it
      # Proxmox gives every new disk a refreservation equal to its full declared
      # size at creation, so the pool's free space is consumed before a block is
      # written. Same field, same meaning, as `sparse` on a dataset below.
      sparse = optional(bool, false)
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
        # Thin-provision disks created on this dataset's `pvesm_id` storage.
        # Without it Proxmox gives every new disk a refreservation equal to its
        # full declared size the moment it is created, so a 450G disk consumes
        # 450G of the dataset `quota` before a block is written and the quota
        # holds exactly one such disk. Only meaningful alongside `pvesm_id`.
        sparse = optional(bool, false)
        # Arbitrary ZFS properties (recordsize, compression, readonly,
        # com.sun:auto-snapshot, …) applied idempotently by ansible-proxmox.
        # Use ZFS canonical forms as strings (e.g. "1M", "zstd", "false").
        properties = optional(map(string), {})
        # Serve this dataset over SMB. The share lives ON the dataset rather than
        # in a separate node-level list, because the map key already identifies
        # both the node and the dataset -- there is nothing left to select and no
        # way for a share to reference a dataset that does not exist.
        smb = optional(object({
          share_name = string
          comment    = optional(string)
          # Samba group syntax only ("@nas", "+nas") -- enforced below. A share
          # must authorize by GROUP, never by naming an account, because the
          # login name is a secret and this object is the desired state.
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

  # A share may authorize only by GROUP. Samba reads a bare word in
  # valid_users as a USERNAME, so allowing one here would put a login name into
  # the desired-state object and into the rendered smb.conf -- the exact
  # publication `managed_users.secret_prefix` exists to prevent. "@grp" is a
  # unix/NIS group and "+grp" forces the unix group; both are safe.
  validation {
    condition = alltrue([
      for node, cfg in var.node_storage : alltrue([
        for pool, p in cfg.pools : alltrue([
          for ds, d in p.datasets :
          d.smb == null || d.smb.valid_users == null ||
          alltrue([
            for u in split(",", d.smb.valid_users) :
            startswith(trimspace(u), "@") || startswith(trimspace(u), "+")
          ])
        ])
      ])
    ])
    error_message = "smb.valid_users must list only groups (\"@nas\" or \"+nas\"); a bare name is read by Samba as a username, and a login name must not appear in the desired state."
  }

  # Two accounts sharing a secret_prefix would resolve to the same OpenBao
  # fields and silently collapse into one account.
  validation {
    condition = alltrue([
      for node, cfg in var.node_storage :
      cfg.smb == null ? true :
      length(cfg.smb.managed_users) == length(distinct([
        for u in cfg.smb.managed_users : u.secret_prefix
      ]))
    ])
    error_message = "Each managed_users.secret_prefix must be unique within a node; duplicates resolve to the same OpenBao username/password fields."
  }

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
