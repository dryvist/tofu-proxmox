# OCI image reference for the YouTrack guest. The image is pulled onto every
# commissioned node as a vztmpl tarball (ct_templates.tf), so the guest can
# start on any node it relocates to. The reference is pinned by version tag.

variable "youtrack_oci_reference" {
  description = "OCI reference of the YouTrack image. The youtrack guest boots from it through the youtrack-oci.tar template. Must be a YYYY.N.BUILD version tag."
  type        = string
  # Tag pin only: digest pinning waits on provider support (bpg/proxmox 0.116.1 rejects @sha256 references).
  # An image bump does not replace the container (template_file_id is in ignore_changes); upgrades run through the OCI app upgrade procedure.
  # renovate: datasource=docker depName=jetbrains/youtrack versioning=loose
  default = "jetbrains/youtrack:2026.2.19728"

  validation {
    condition     = can(regex("^[a-z0-9._/-]+:[0-9]{4}\\.[0-9]+\\.[0-9]+$", var.youtrack_oci_reference))
    error_message = "youtrack_oci_reference must be a YYYY.N.BUILD version tag, e.g. jetbrains/youtrack:2026.2.19728."
  }
}
