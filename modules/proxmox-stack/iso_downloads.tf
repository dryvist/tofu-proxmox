# Install media resolved against `iso_base_url`, a read-only object prefix, and
# addressed by versioned object names. See var.iso_base_url for why the host is
# configured rather than composed here.
#
# Every object is pinned by sha256, so a file whose content does not match is
# rejected at download time instead of producing a broken template. Update the
# checksum and the versioned object name together whenever the content changes.
#
# upload_timeout is raised above the 600s provider default, which is sized for
# images an order of magnitude smaller than these.

resource "proxmox_download_file" "virtio_iso" {
  content_type       = "iso"
  datastore_id       = var.datastore_iso
  node_name          = var.proxmox_node
  file_name          = "virtio-win.iso"
  url                = "${var.iso_base_url}/drivers/virtio-win-0.1.285.iso"
  checksum           = "e14cf2b94492c3e925f0070ba7fdfedeb2048c91eea9c5a5afb30232a3976331"
  checksum_algorithm = "sha256"
  upload_timeout     = 3600
}

resource "proxmox_download_file" "win10_iso" {
  content_type       = "iso"
  datastore_id       = var.datastore_iso
  node_name          = var.proxmox_node
  file_name          = "Windows10.iso"
  url                = "${var.iso_base_url}/windows/Windows10-22H2.iso"
  checksum           = "a6f470ca6d331eb353b815c043e327a347f594f37ff525f17764738fe812852e"
  checksum_algorithm = "sha256"
  upload_timeout     = 3600
}

resource "proxmox_download_file" "win11_iso" {
  content_type       = "iso"
  datastore_id       = var.datastore_iso
  node_name          = var.proxmox_node
  file_name          = "Windows11.iso"
  url                = "${var.iso_base_url}/windows/Windows11-25H2.iso"
  checksum           = "768984706b909479417b2368438909440f2967ff05c6a9195ed2667254e465e3"
  checksum_algorithm = "sha256"
  upload_timeout     = 3600
}

resource "proxmox_download_file" "win25_iso" {
  content_type       = "iso"
  datastore_id       = var.datastore_iso
  node_name          = var.proxmox_node
  file_name          = "WindowsServer2025.iso"
  url                = "${var.iso_base_url}/windows/WindowsServer2025.iso"
  checksum           = "7b052573ba7894c9924e3e87ba732ccd354d18cb75a883efa9b900ea125bfd51"
  checksum_algorithm = "sha256"
  upload_timeout     = 3600
}
