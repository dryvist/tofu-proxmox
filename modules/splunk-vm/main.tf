terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.111"
    }
  }
}

# =============================================================================
# CRITICAL — SPLUNK BOOT + LEGACY DATA DISKS ARE NOT BACKED UP
# =============================================================================
# The boot disk and the legacy virtio1 (200G) data disk carry live Splunk state
# that is NOT backed up anywhere. Treat EVERY operation on this VM as
# potentially data-destructive:
#   - NEVER destroy/recreate the VM. `prevent_destroy = true` is set below for
#     exactly this reason — do not remove it.
#   - NEVER touch the boot disk or virtio1. Only the 4MB cloud-init drive is
#     safe to modify.
#   - AVOID `cloud-init clean` + reboot here. It re-runs cloud-init; it is only
#     data-safe because the cloud-init user-data has no disk_setup/fs_setup/
#     growpart today — re-verify that before ever relying on it.
#   - The guest network/OS config is Ansible-owned post-boot (cloud-init is
#     first-boot only); tofu manages the NIC VLAN tag, not the guest IP, which
#     is why initialization[0].ip_config is in ignore_changes below.
#
# Backup posture per disk (see var.tiered_disks / docs/ARCHITECTURE.md):
#   - boot + virtio1: backup=1 but NO backup job runs yet. ACTION NEEDED — stand
#     up a real backup job (PBS / zfs-send) BEFORE the next risky change.
#   - fast-splunk (virtio2, hot/warm) and bulk-splunk (virtio3, cold): both
#     backup=false BY DESIGN. Index data is reconstructible and a block backup
#     would roughly double the storage consumed for no resilience gain;
#     durability comes from the Backblaze B2 frozen archive (configured
#     Splunk-side), never from vzdump. NOT an open item.
# =============================================================================

# Render cloud-init configuration with secrets and config files
# Firewall is managed by Proxmox firewall module, not guest-level iptables
locals {
  cloud_init_config = templatefile("${path.module}/templates/cloud-init.yml.tpl", {
    hostname = var.name
    domain   = var.domain
  })
}

resource "proxmox_virtual_environment_vm" "splunk_vm" {
  vm_id       = var.vm_id
  node_name   = var.node_name
  name        = var.name
  description = "Splunk Enterprise Docker - ${var.name}"

  tags = [
    "terraform",
    "splunk",
    "docker",
    "enterprise"
  ]

  pool_id    = var.pool_id
  protection = false

  # Startup configuration
  on_boot = true

  # Startup order derives from the VMID itself, same convention as
  # proxmox-vm/proxmox-container: legacy 3-digit IDs (<1000) start in that
  # order; 6-digit IDs use their thousands prefix.
  startup {
    order    = var.vm_id < 1000 ? var.vm_id : floor(var.vm_id / 1000)
    up_delay = var.startup_delay
  }

  agent {
    enabled = true
    timeout = "15m"
    trim    = true
    type    = "virtio"
  }

  # Governs what a node_name change means: migrate the VM, or destroy and
  # recreate it. The provider forces replacement unless this is true, and a
  # replacement here would destroy the index volumes.
  migrate = var.migrate

  # CPU configuration. "host" exposes every host CPU feature with zero emulation
  # overhead, but it also pins the guest to one CPU vendor: a "host" guest cannot
  # migrate between an AMD node and an Intel one, because the feature set it was
  # booted with does not exist on the destination. A portable model name
  # (x86-64-v2 / v3) trades a small amount of that for the ability to move.
  cpu {
    cores      = var.cpu_cores
    type       = var.cpu_type
    hotplugged = 0
  }

  memory {
    dedicated = var.memory
    floating  = var.memory
  }

  # Boot disk: virtio0 interface uses VirtIO SCSI controller
  disk {
    datastore_id = var.datastore_id
    interface    = "virtio0"
    size         = var.boot_disk_size
    file_format  = "raw"
    iothread     = true
    ssd          = false
    discard      = "ignore"
  }

  # Data disk for Splunk index storage (mounted at /opt/splunk)
  dynamic "disk" {
    for_each = var.data_disk_size > 0 ? [1] : []
    content {
      datastore_id = var.datastore_id
      interface    = "virtio1"
      size         = var.data_disk_size
      file_format  = "raw"
      iothread     = true
      ssd          = false
      discard      = "ignore"
    }
  }

  # Tiered Splunk data disks (fast-splunk hot/warm, bulk-splunk cold). Same
  # map-driven shape as modules/proxmox-vm's additional_disks, so new tiers are
  # added by map entry, not by another hardcoded block. bpg keys disks by their
  # explicit `interface` (virtio2/virtio3), so map iteration order is irrelevant.
  # Both tiers carry backup = false: index data is reconstructible and a block
  # backup would roughly double the storage consumed for no resilience gain.
  # Durability comes from the Backblaze B2 frozen archive (configured
  # Splunk-side in ansible-splunk), never from Proxmox vzdump.
  # NOTE: while `ignore_changes = [disk]` is active (see lifecycle below), adding
  # these blocks produces NO plan diff — attaching them is a human-supervised
  # step, documented privately.
  dynamic "disk" {
    for_each = var.tiered_disks
    content {
      datastore_id = disk.value.datastore_id
      interface    = disk.value.interface
      size         = disk.value.size
      backup       = disk.value.backup
      file_format  = disk.value.file_format
      iothread     = disk.value.iothread
      ssd          = disk.value.ssd
      discard      = disk.value.discard
    }
  }

  network_device {
    bridge   = var.bridge
    model    = "virtio"
    firewall = true
    # 802.1Q tag onto the service VLAN (siem). Null/0 = untagged native.
    # Mirrors the container NIC pattern (vlan_id = vlan_ids[guest.vlan]); without
    # this the VM sits on vmbr0's untagged native instead of its own VLAN.
    vlan_id = var.vlan_id
  }

  clone {
    vm_id = var.template_id
  }

  initialization {
    datastore_id = var.datastore_id

    # Explicit resolver, the VM's own gateway — see modules/proxmox-vm for rationale.
    dynamic "dns" {
      for_each = var.domain != "" || var.gateway != "" ? [1] : []
      content {
        domain  = var.domain != "" ? var.domain : null
        servers = var.gateway != "" ? [var.gateway] : null
      }
    }

    ip_config {
      ipv4 {
        address = var.ip_address
        gateway = var.gateway
      }
    }

    user_account {
      username = "debian"
      keys     = var.ssh_public_key != "" ? [var.ssh_public_key] : []
    }

    # Cloud-init user data with Splunk Docker configuration
    user_data_file_id = proxmox_virtual_environment_file.cloud_init.id
  }

  operating_system {
    type = "l26"
  }

  # Timeout configurations - 30 min for clone/create, 15 min standard for others
  timeout_clone       = 1800 # 30 min - disk copy can be slow
  timeout_create      = 1800 # 30 min - cloud-init execution
  timeout_migrate     = 900  # 15 min - standard
  timeout_reboot      = 900  # 15 min - standard
  timeout_shutdown_vm = 900  # 15 min - standard
  timeout_start_vm    = 900  # 15 min - standard
  timeout_stop_vm     = 900  # 15 min - standard

  lifecycle {
    prevent_destroy       = true
    create_before_destroy = false
    ignore_changes = [
      # Ignore changes to the source template after initial clone.
      # The VM is managed by Ansible post-creation; Packer rebuilds of the base
      # template should not trigger VM replacement.
      clone,
      # Cloud-init runs only at first boot; Ansible handles all post-boot config.
      # Ignore changes to user_data_file_id so cloud-init template updates
      # don't force VM replacement on an already-running VM.
      initialization[0].user_data_file_id,
      # Same reason: a VLAN change alters cloud-init ip_config, which would make
      # bpg rebuild the cloud-init drive — and that fails on the non-removable
      # ide2 disk. Ansible owns post-boot networking, so ignore the drift.
      initialization[0].ip_config,
      # Same failure mode for resolvers: a dns diff makes bpg rebuild the
      # cloud-init drive too — on THIS VM that rebuild took 15+ minutes and
      # rebooted production Splunk during the 2026-06-11 apply. Resolvers on the
      # running VM are Ansible-owned; the dns block only matters at first boot.
      initialization[0].dns,
      # The live disk layout diverged from this module out-of-band: the boot
      # disk is scsi0/50G (not virtio0/25G), and the empty leftover disk-1 was
      # reaped directly on the host. bpg keys disk blocks positionally and tofu
      # state tracks only the virtio1 data disk, so ANY disk reconciliation tries
      # to unplug the live scsi0 bootdisk (Proxmox HTTP 400) and would reinterpret
      # the 200G data disk. Disk sizing/layout is owned outside tofu (Proxmox +
      # the ansible sanoid/syncoid protection layer), so ignore disk drift. Revisit
      # if tofu is ever made the source of truth for the disk split (see #247).
      #
      # FINDING (var.tiered_disks interaction): narrowing this to a positional
      # index (e.g. `disk[0]`, `disk[1]`) to un-ignore only the new virtio2/virtio3
      # tiers is NOT viable on bpg/proxmox. bpg keys disk blocks by their
      # `interface` value, not positionally, so a numeric `ignore_changes` index
      # does not stably map to a given disk across refreshes — Terraform's
      # ignore_changes indexing is undefined for set-like nested blocks. Keeping
      # the whole `disk` attribute ignored is therefore the only safe state today.
      # CONSEQUENCE: while `disk` stays ignored, the var.tiered_disks blocks above
      # produce NO plan diff and will NOT attach on apply.
      # Attaching them requires reconciling the live disks into state and then
      # removing this entry under a reviewed apply, so bpg matches existing disks
      # by interface. That is a human-supervised procedure, documented privately.
      disk,
    ]
  }
}

# Cloud-init configuration file stored in Proxmox
resource "proxmox_virtual_environment_file" "cloud_init" {
  content_type = "snippets"
  datastore_id = var.snippets_datastore_id
  node_name    = var.node_name

  source_raw {
    data      = local.cloud_init_config
    file_name = "${var.name}-cloud-init.yml"
  }
}
