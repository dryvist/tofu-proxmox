# Base-template variables for the Debian cloud-init image the guests clone
# from. Split out of variables-storage.tf, which had grown to mix storage
# declarations with template plumbing (and past the shared 12 KB file gate).
# See base_templates.tf for the resources these feed.

variable "debian_template_id" {
  type        = number
  description = "VMID of the Debian cloud-init base template that guests clone from"
  default     = 9001
}

variable "debian_template_name" {
  type        = string
  description = "Name of the Debian cloud-init base template"
  default     = "debian-13-cloudimg"
}

variable "debian_cloudimg_file_name" {
  type        = string
  description = "File name the Debian cloud image is stored as. Must carry an extension the `import` content type accepts (.qcow2/.raw/.vmdk/.ova). Changing this re-downloads the image."
  # Proxmox validates the stored filename against the content type it is filed
  # under (PVE::Storage::UPLOAD_IMPORT_EXT_RE_1 for `import`), and rejects a
  # mismatch with a bare "Parameter verification failed. (filename: wrong file
  # extension)" that aborts the whole apply before the inventory publishes.
  # Keep this extension and base_templates.tf's content_type in step.
  default = "debian-13-generic-amd64.qcow2"
}

variable "debian_cloudimg_url" {
  type        = string
  description = "Source URL for the Debian generic cloud image"
  default     = "https://cloud.debian.org/images/cloud/trixie/latest/debian-13-generic-amd64.qcow2"
}

variable "template_bridge" {
  type        = string
  description = "Network bridge attached to base templates"
  default     = "vmbr0"
}
