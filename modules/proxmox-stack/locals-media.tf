# Media-tier tag-filter locals, split from locals.tf to keep that file under
# the shared _file-size 12 KB error threshold; locals merge across files.
locals {
  # LAN-only media guests (media tag), EXCLUDING the VPN-locked downloader
  # (vpn tag). The downloader's fail-closed in-guest killswitch is its enforced
  # network boundary — stacking a hypervisor DROP policy underneath the tunnel
  # would add a second, independently-managed failure mode without adding
  # coverage (the killswitch already denies every flow the guest firewall
  # would). See docs/ARCHITECTURE.md (media pool firewall boundary).
  media_container_ids = {
    for k, v in var.containers : k => v.vm_id
    if contains(coalesce(try(v.tags, null), []), local.firewall_container_tags.media)
    && !contains(coalesce(try(v.tags, null), []), local.firewall_container_tags.vpn)
  }
}
