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
