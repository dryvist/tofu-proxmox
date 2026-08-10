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
  # `import`, not `iso`. Proxmox types a volume by the content directory it
  # sits in, and refuses an iso-type volume as a disk import source: "has wrong
  # type 'iso' - needs to be 'images' or 'import'". It also validates the file
  # extension per content type — `iso` accepts only .iso/.img while `import`
  # accepts .qcow2/.raw/.vmdk/.ova, so the two settings have to move together.
  #
  # Storing it as .img under `iso` gets the download past validation and then
  # fails one step later at disk creation, which is how this first presented.
  # Both failures aborted the apply before the Ansible inventory published.
  #
  # This requires `import` in the datastore's content list. Not yet expressed in
  # node_storage, which models ZFS pools rather than dir-storage content types.
  content_type = "import"
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
    import_from = "${var.datastore_iso}:import/${proxmox_download_file.debian_cloudimg.file_name}"
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
