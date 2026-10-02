# Downloads each VM's disk_image (see variables.tf) onto its own node as a
# PVE `import`-type volume, so it can be attached below as disk.import_from.
# Mirrors the existing debian_cloudimg pattern in
# modules/proxmox-stack/base_templates.tf: content_type = "import", and
# import_from built from datastore_id + file_name rather than the download
# resource's `id`, which is not in the "datastore:content/file" form the
# disk block expects.
resource "proxmox_download_file" "disk_image" {
  for_each = { for k, v in var.vms : k => v if v.disk_image != null }

  content_type = "import"
  datastore_id = coalesce(each.value.boot_disk.datastore_id, var.default_datastore)
  node_name    = each.value.node_name
  file_name    = each.value.disk_image.file_name
  url          = each.value.disk_image.url

  checksum                = each.value.disk_image.checksum
  checksum_algorithm      = each.value.disk_image.checksum_algorithm
  decompression_algorithm = each.value.disk_image.decompression_algorithm
}
