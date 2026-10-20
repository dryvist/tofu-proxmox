# Docker-in-LXC feature derivation.
#
# A container tagged `docker` runs Docker inside the LXC, which needs `nesting`
# plus `keyctl` + `fuse` for the fuse-overlayfs storage driver this homelab uses
# on ZFS-backed LXCs (the ansible-proxmox-apps registry-mirror play sets
# storage-driver=fuse-overlayfs).
#
# Only `nesting` is derived from the tag, because it is the one container feature
# an API token may set at create time. `keyctl` and `fuse` are root@pam-only: a
# token gets HTTP 403 ("changing feature flags (except nesting) is only allowed
# for root@pam"), and BPG does not set them over its SSH connection either. They
# are applied out-of-band, post-create, by the ansible-proxmox `lxc_features` role
# (`pct set --features` over root SSH), and the container's
# `lifecycle ignore_changes = [features]` keeps Terraform from reverting them.
# Deriving keyctl/fuse from the tag (PR #457) made the create call send them and
# 403 every *new* docker guest — so they are nesting-only here.
#
# The tag only ever ADDS `nesting`: any explicitly-declared feature still applies
# (logical OR), so a non-docker container is unaffected.
locals {
  container_migrate = {
    for k, c in var.containers : k => coalesce(c.migrate, c.ha_replication_target != null)
  }

  effective_features = {
    for k, c in var.containers : k => {
      nesting = c.features.nesting || contains(c.tags, "docker")
      keyctl  = c.features.keyctl
      fuse    = c.features.fuse
      mount   = c.features.mount
    }
  }
}
