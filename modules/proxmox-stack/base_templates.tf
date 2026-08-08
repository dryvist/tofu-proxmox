# Debian cloud-init base template.
#
# This template is built from a cloud IMAGE, not an installer, so it is declared
# here rather than in the packer-proxmox repository: no Packer builder imports a
# disk image. `proxmox-iso` boots an installer and `proxmox-clone` needs a VM
# that already exists, so expressing this in Packer would mean writing an
# ISO+preseed install to replace a working import.
#
# This replaces the hand-run `qm create` / `qm importdisk` / `qm template`
# recipe that used to live in docs/TEMPLATE_CREATION.md.

resource "proxmox_download_file" "debian_cloudimg" {
  # Cloud images live under the `iso` content type; that is the datastore
  # content this node already has enabled, and it is where import_from reads
  # from. The file is a qcow2, not an installer ISO.
  content_type = "iso"
  datastore_id = var.datastore_iso
  node_name    = var.proxmox_node
  file_name    = var.debian_cloudimg_file_name
  url          = var.debian_cloudimg_url

  # Cloud images are republished in place under `latest`, so the checksum moves
  # with them. Re-download only when the declared file name changes.
  overwrite = false
}

resource "proxmox_virtual_environment_vm" "debian_base_template" {
  vm_id     = var.debian_template_id
  name      = var.debian_template_name
  node_name = var.proxmox_node
  template  = true
  # A template is never started; without this the provider waits on a boot that
  # will not happen.
  started = false

  description = "Debian cloud-init base template. Managed by OpenTofu - do not edit on the node."

  agent {
    enabled = true
  }

  cpu {
    # Matches the manual recipe this replaces. Not `host`, because a template
    # cloned across dissimilar nodes must not pin the build node's silicon.
    type  = "x86-64-v2-AES"
    cores = 2
  }

  memory {
    dedicated = 2048
  }

  scsi_hardware = "virtio-scsi-pci"

  disk {
    datastore_id = var.datastore_default
    # This is the qm importdisk step: attach the downloaded cloud image as the
    # boot disk rather than installing onto an empty one. The identifier is
    # built rather than taken from the resource's `id`, which is not in the
    # `datastore:content/file` form this field requires.
    import_from = "${var.datastore_iso}:iso/${proxmox_download_file.debian_cloudimg.file_name}"
    interface   = "scsi0"
    discard     = "on"
    iothread    = true
    ssd         = true
  }

  # Replaces `qm set --ide2 <storage>:cloudinit`.
  initialization {
    datastore_id = var.datastore_default
    interface    = "ide2"

    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }
  }

  network_device {
    bridge = var.template_bridge
    model  = "virtio"
  }

  # Replaces `qm set --serial0 socket --vga serial0`. Cloud-init writes its
  # progress to the serial console, so without this a failed first boot is
  # invisible.
  serial_device {}

  vga {
    type = "serial0"
  }

  operating_system {
    type = "l26"
  }

  lifecycle {
    ignore_changes = [
      # The provider reports the imported disk's source on every read, which
      # would otherwise plan a replacement of a template that clones depend on.
      disk[0].import_from,
    ]
  }
}
