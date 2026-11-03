# Non-Debian LXC templates.
#
# Every LXC in this estate shares one Debian template: main.tf composed it once
# from var.proxmox_ct_template_debian, and there was no per-guest selector at
# all until the ct_template field was added alongside this file. The NixOS
# guests that run herdr are the first exception.
#
# WHY EVERY NODE. A vztmpl on `local` is node-local, and an HA guest relocates.
# A template present only on the node the guest was created on turns a failover
# into a guest that cannot start. The estate's Debian template is placed on
# each node by ansible-proxmox for the same reason; this does it in code.
#
# WHERE THE FILE COMES FROM. nix-ai builds it —
#   nix build github:dryvist/nix-ai#herdr-lxc-template
# via nixpkgs' own nixos/modules/virtualisation/proxmox-lxc.nix (NOT
# nixos-generators, which was deprecated in NixOS 25.05 and archived) — and
# publishes the tarball as a release asset. Pin the release URL and its sha256
# together, exactly like the install media in iso_downloads.tf: a file whose
# content does not match is rejected at download time rather than producing a
# guest that half-boots.
#
# Leave nixos_ct_template_url empty to disable this entirely; the guests that
# reference the template simply cannot be declared until it is set.

resource "proxmox_download_file" "nixos_ct_template" {
  for_each = var.nixos_ct_template_url == "" ? {} : {
    for name, node in var.nodes : name => node if node.commissioned
  }

  content_type       = "vztmpl"
  datastore_id       = var.datastore_iso
  node_name          = each.key
  file_name          = var.nixos_ct_template_file_name
  url                = var.nixos_ct_template_url
  checksum           = var.nixos_ct_template_sha256
  checksum_algorithm = "sha256"
  upload_timeout     = 1800

  # A template already staged by hand should be adopted, not clobbered — the
  # same posture base_templates.tf takes with the Debian cloud image.
  overwrite = false
}

# OCI application images. Each key is pulled onto every commissioned node as a
# vztmpl tarball named by that key, so a guest's ct_template selects it the way
# it selects the NixOS template above. Every-node placement for the same reason:
# a relocated HA guest must find its template on the node it lands on.
locals {
  oci_ct_templates = {
    # Stable file name: a version bump changes the tarball, not the guest's
    # ct_template, so the guest declaration does not change with the pin.
    "youtrack-oci.tar" = var.youtrack_oci_reference
  }

  # Only templates some container selects are pulled, so an unused pin never
  # puts a pull (and its node privileges) on the apply path.
  oci_ct_templates_in_use = {
    for file, reference in local.oci_ct_templates : file => reference
    if contains([for c in values(var.containers) : try(c.ct_template, null)], file)
  }

  oci_ct_template_pulls = merge([
    for name, node in var.nodes : {
      for file, reference in local.oci_ct_templates_in_use : "${name}/${file}" => {
        node_name = name
        file_name = file
        reference = reference
      }
    } if node.commissioned
  ]...)
}

resource "proxmox_oci_image" "oci_ct_template" {
  for_each = local.oci_ct_template_pulls

  node_name    = each.value.node_name
  datastore_id = var.datastore_iso
  reference    = each.value.reference
  file_name    = each.value.file_name

  # Unlike the NixOS template, this one is pinned in code, so a copy whose size
  # no longer matches the reference is replaced, not adopted.
  overwrite      = true
  upload_timeout = 1800
}
