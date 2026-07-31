terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.111"
    }
  }
}

resource "proxmox_virtual_environment_container" "containers" {
  for_each = var.containers

  vm_id       = each.value.vm_id
  node_name   = each.value.node_name
  description = each.value.description != null ? each.value.description : "TF CT ${each.value.hostname} - ${var.environment}"

  # Tags with environment
  tags = concat(
    each.value.tags,
    [var.environment]
  )

  # Pool assignment
  pool_id = each.value.pool_id

  # Unprivileged containers can set features without root@pam
  unprivileged = each.value.unprivileged

  # Protection
  protection = each.value.protection

  # Startup configuration
  start_on_boot = each.value.start_on_boot

  # Startup order derives from the VMID itself: the 6-digit scheme's thousands
  # prefix already encodes dependency priority (e.g. 303000 postgres starts
  # before 517000 hermes), and legacy 3-digit IDs (<1000) are used directly.
  # Lower order starts first. INC-17124/INC-17125: the prior `256 - vm_id`
  # scheme clamped every 6-digit-VMID guest to the same order (0), leaving
  # Proxmox's tiebreak among them undefined.
  startup {
    order    = each.value.vm_id < 1000 ? each.value.vm_id : floor(each.value.vm_id / 1000)
    up_delay = var.startup_delay
  }

  # Container initialization
  initialization {
    hostname = each.value.hostname

    # IP configuration. address is either a CIDR (static, vm_id-derived) or the
    # literal "dhcp" for DNS-first guests; in the DHCP case the caller passes a
    # null gateway (the lease provides one), so gateway is simply omitted.
    dynamic "ip_config" {
      for_each = each.value.ip_config.ipv4_address != null ? [1] : []
      content {
        ipv4 {
          address = each.value.ip_config.ipv4_address
          gateway = each.value.ip_config.ipv4_gateway
        }
      }
    }

    # DNS search domain + resolver. A static guest resolves through its OWN VLAN
    # gateway, which conditionally forwards the internal zone to the resolver
    # fleet — the same thing DHCP guests already receive in their lease.
    #
    # It used to be the resolver addresses themselves. That bakes a copy of the
    # fleet's addressing into every guest at provision time, and cloud-init does
    # not revisit it: rename or renumber a resolver and every guest holding the
    # old list is stale until rebuilt, with nothing reporting it. The gateway is
    # the guest's own and never moves when the fleet changes.
    #
    # Inheriting the node's resolv.conf is NOT the fallback to want — the node
    # sits on its own VLAN, so a guest elsewhere would be pointed at a gateway
    # it may have no route to. Hence an explicit per-guest value.
    #
    # DHCP guests have a null gateway here (the lease supplies both address and
    # resolver), so servers is omitted for them and the lease wins.
    dynamic "dns" {
      for_each = var.domain != "" || each.value.ip_config.ipv4_gateway != null ? [1] : []
      content {
        domain  = var.domain != "" ? var.domain : null
        servers = each.value.ip_config.ipv4_gateway != null ? [each.value.ip_config.ipv4_gateway] : null
      }
    }

    # User account configuration (only if keys are provided)
    dynamic "user_account" {
      for_each = length(lookup(each.value.user_account, "keys", [])) > 0 || lookup(each.value.user_account, "password", "") != "" ? [1] : []
      content {
        password = lookup(each.value.user_account, "password", "")
        keys     = lookup(each.value.user_account, "keys", [])
      }
    }
  }

  # CPU configuration
  cpu {
    cores = each.value.cpu_cores
  }

  # Memory configuration.
  #
  # swap defaults to the container's own memory cap rather than being left unset.
  # Unset lands on 0, which sets memory.swap.max=0 in the container's cgroup: the
  # guest cannot page out AT ALL, so a spike past `dedicated` is an immediate
  # cgroup OOM-kill even when the host has tens of GB of free swap. Measured
  # 2026-07-29: 12 of 13 running containers on one node had memory.swap.max=0
  # while the host sat on 95 GiB of completely unreachable swap.
  #
  # An explicit memory_swap = 0 is still honoured (coalesce only skips null), so a
  # guest that genuinely must stay resident can opt out.
  memory {
    dedicated = each.value.memory_dedicated
    swap      = coalesce(each.value.memory_swap, each.value.memory_dedicated)
  }

  # Root disk
  disk {
    datastore_id = coalesce(each.value.root_disk.datastore_id, var.default_datastore)
    size         = coalesce(each.value.root_disk.size, 8)
  }

  # Additional mount points
  # `size` is only set for managed-volume mounts. Host-directory bind-mounts
  # (volume = "/example-pool/media") must omit size — passing a size to a bind-mount
  # is rejected by the Proxmox API.
  dynamic "mount_point" {
    for_each = each.value.mount_points
    content {
      volume = mount_point.value.volume
      size   = mount_point.value.size
      path   = mount_point.value.path
    }
  }

  # Device passthrough (e.g. /dev/net/tun for WireGuard inside the LXC).
  dynamic "device_passthrough" {
    for_each = each.value.device_passthrough
    content {
      path       = device_passthrough.value.path
      mode       = device_passthrough.value.mode
      uid        = device_passthrough.value.uid
      gid        = device_passthrough.value.gid
      deny_write = device_passthrough.value.deny_write
    }
  }

  # Network interfaces
  dynamic "network_interface" {
    for_each = each.value.network_interfaces
    content {
      name     = network_interface.value.name
      bridge   = network_interface.value.bridge
      firewall = network_interface.value.firewall
      vlan_id  = network_interface.value.vlan_id
      # Deterministic MAC for DHCP-first guests; null for static guests lets the
      # provider keep its auto-generated MAC (no churn on existing containers).
      mac_address = network_interface.value.mac_address
    }
  }

  # Operating system
  operating_system {
    template_file_id = each.value.template_file_id
    type             = each.value.os_type
  }

  # Container features. nesting/keyctl/fuse are DERIVED from the `docker` tag in
  # locals.tf (local.effective_features) so docker guests get the full Docker-in-LXC
  # set automatically; explicit per-container features still apply on top.
  # Only emit the block when any value is set. Creating privileged containers with a
  # features block requires root@pam.
  dynamic "features" {
    for_each = (
      local.effective_features[each.key].nesting
      || local.effective_features[each.key].keyctl
      || local.effective_features[each.key].fuse
      || length(local.effective_features[each.key].mount) > 0
    ) ? [1] : []
    content {
      nesting = local.effective_features[each.key].nesting
      keyctl  = local.effective_features[each.key].keyctl
      fuse    = local.effective_features[each.key].fuse
      mount   = local.effective_features[each.key].mount
    }
  }

  lifecycle {
    create_before_destroy = false
    ignore_changes = [
      # Ignore changes to immutable attributes after import
      # These can only be changed by replacing the container. The whole
      # user_account block (not just its attributes) must be ignored: an
      # imported guest has no user_account in state at all, so a declared
      # block is a 0->1 count diff that forces replacement — attribute-level
      # ignores do not cover it.
      initialization[0].user_account,
      operating_system[0].template_file_id,
      pool_id,
      # Ignore the runtime started status - this is a computed field that reflects
      # whether the container is currently running. We manage boot behavior via
      # start_on_boot, not runtime state.
      started,
      # Ignore features drift on existing containers — Proxmox returns HTTP 500
      # "no options specified" when an update sends no meaningful feature changes.
      # Features are only set at creation time (privileged containers require root@pam).
      features,
      # Ignore mount_point drift. HOST bind-mounts (e.g. the media stack's single
      # /bulk/data mount) are root@pam-only, so the BPG API token cannot set them —
      # they are applied post-creation by the ansible-proxmox `media_lxc_features`
      # role, not by terraform. Without this, every refresh sees the live mount as
      # drift and tries to strip it, which forces replacement of the (data-bearing)
      # media containers. Same rationale as `features` and the splunk-vm boot disk
      # (terraform-proxmox #390). Storage-VOLUME mounts declared in deployment.json
      # are still created at provision time; only post-creation reconciliation is
      # ignored (mounts are effectively set-once here).
      mount_point,
      # Ignore idmap drift, same rationale as mount_point. The media containers'
      # uid/gid passthrough (e.g. gid 13000 ↔ 13000 for the /data mount) is applied
      # post-creation by the ansible-proxmox `media_lxc_features` role — it is
      # root@pam-only, so the BPG API token cannot set it. Without this, every
      # refresh reads the live idmap back into state and tries to strip it, which
      # would revert the media stack's write access. idmap is not declared in
      # deployment.json, so this only suppresses out-of-band reconciliation.
      idmap,
    ]
  }
}
