# Media tier guest firewall. The LAN-only media guests (PVRs, streaming,
# request UI, insights dashboard) get the standard DROP/DROP companion:
# internal access, their own web port from internal, and internal + HTTPS
# egress (cross-app wiring lives on internal networks; metadata providers and
# container-image pulls need outbound TLS).
#
# The VPN-locked downloader is deliberately ABSENT: its fail-closed in-guest
# killswitch is the enforced boundary (root locals-media.tf excludes it from
# var.media_container_ids by tag).
#
# Inbound web ports are attached as per-guest inline rules keyed by container
# name — NOT one shared security group — so no guest exposes a sibling's port.
# A media guest with no entry in the map gets no inbound web allowance at all
# (safe default for a future addition). Ports are DRY from pipeline_constants.
locals {
  media_ports = var.pipeline_constants.media_ports

  media_web_rules = {
    sonarr  = { dport = tostring(local.media_ports.sonarr_web), comment = "Sonarr web/API (TCP ${local.media_ports.sonarr_web}) from internal" }
    radarr  = { dport = tostring(local.media_ports.radarr_web), comment = "Radarr web/API (TCP ${local.media_ports.radarr_web}) from internal" }
    plex    = { dport = tostring(local.media_ports.plex_web), comment = "Plex web/streaming (TCP ${local.media_ports.plex_web}) from internal" }
    seerr   = { dport = tostring(local.media_ports.seerr_web), comment = "Seerr request UI/API (TCP ${local.media_ports.seerr_web}) from internal" }
    sortarr = { dport = tostring(local.media_ports.sortarr_web), comment = "Sortarr insights UI (TCP ${local.media_ports.sortarr_web}) from internal" }
  }
}

resource "proxmox_virtual_environment_firewall_options" "media_container" {
  for_each = var.media_container_ids

  node_name     = var.node_name
  container_id  = each.value
  enabled       = local.firewall_defaults.enabled
  input_policy  = local.firewall_defaults.input_policy
  output_policy = local.firewall_defaults.output_policy
  log_level_in  = local.firewall_defaults.log_level_in
  log_level_out = local.firewall_defaults.log_level_out

  # DHCP-first guests behind DROP policies need their own DHCPDISCOVER/OFFER
  # allowed or they never lease their reserved media-VLAN address.
  dhcp = true

  depends_on = [proxmox_virtual_environment_cluster_firewall.main]
}

resource "proxmox_virtual_environment_firewall_rules" "media_container" {
  for_each = var.media_container_ids

  node_name    = var.node_name
  container_id = each.value

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.internal_access.name
    comment        = "Internal access (SSH, ICMP)"
  }

  # Per-guest web/API port from internal networks (Traefik ingress, LAN
  # clients, and the request UI's cross-app API calls are all internal).
  dynamic "rule" {
    for_each = contains(keys(local.media_web_rules), each.key) ? [local.media_web_rules[each.key]] : []
    content {
      type    = "in"
      action  = "ACCEPT"
      proto   = "tcp"
      dport   = rule.value.dport
      source  = local.internal_src
      comment = rule.value.comment
    }
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.outbound_internal.name
    comment        = "Outbound to internal (cross-app wiring, DNS, apt proxy)"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.outbound_https.name
    comment        = "Outbound HTTPS (metadata providers, image pulls)"
  }

  depends_on = [proxmox_virtual_environment_firewall_options.media_container]
}
