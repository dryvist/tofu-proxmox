# =============================================================================
# Honeypot container firewall (per-VLAN OpenCanary tripwires + apprise gateway)
# =============================================================================
#
# Two roles share the `honeypot` tag and this resource set:
#
#   * tripwires (honeypot, NOT notify) — emulate decoy services on every VLAN.
#     input DROP + honeypot_services (ACCEPT+log the decoy ports) so any touch
#     alerts; egress restricted to internal (outbound_internal) so a poked
#     sensor can reach the notify gateway (Path A) and HAProxy syslog 519
#     (Path B) but can NEVER beacon to the internet.
#
#   * notify gateway (honeypot + notify) — the apprise-api alert sink. input
#     DROP + honeypot_notify_services (just :8000); output ACCEPT so it can
#     fan out to Slack / Pushover / ntfy.sh (same open-egress posture as the
#     Mailpit/ntfy notification containers).
#
# A guest is the notify gateway iff its key is in honeypot_notify_container_ids
# (a subset of honeypot_container_ids). Membership drives both the per-guest
# output_policy and which rule set applies — mirroring how pipeline_container
# grants Cribl-Edge-only HTTPS egress within one shared resource.

locals {
  # Honeypot decoy surface: the low-interaction services each per-VLAN OpenCanary
  # tripwire emulates. ACCEPT+log from internal so any touch on a fake service
  # trips an alert (the whole point — these are NOT real services). SSH (22) is
  # already opened by internal_access. Ports are DRY from honeypot_ports. (Defined
  # here rather than locals.tf to keep that file under the 12 KB size gate.)
  honeypot_services_rules = [
    { proto = "tcp", dport = tostring(local.honeypot_ports.ftp), source = local.internal_src, comment = "Honeypot FTP decoy from internal" },
    { proto = "tcp", dport = tostring(local.honeypot_ports.telnet), source = local.internal_src, comment = "Honeypot Telnet decoy from internal" },
    { proto = "tcp", dport = tostring(local.honeypot_ports.http), source = local.internal_src, comment = "Honeypot HTTP decoy from internal" },
    { proto = "tcp", dport = tostring(local.honeypot_ports.https), source = local.internal_src, comment = "Honeypot HTTPS decoy from internal" },
    { proto = "tcp", dport = tostring(local.honeypot_ports.smb), source = local.internal_src, comment = "Honeypot SMB decoy from internal" },
    { proto = "tcp", dport = tostring(local.honeypot_ports.mssql), source = local.internal_src, comment = "Honeypot MSSQL decoy from internal" },
    { proto = "tcp", dport = tostring(local.honeypot_ports.mysql), source = local.internal_src, comment = "Honeypot MySQL decoy from internal" },
    { proto = "tcp", dport = tostring(local.honeypot_ports.postgres), source = local.internal_src, comment = "Honeypot PostgreSQL decoy from internal" },
    { proto = "tcp", dport = tostring(local.honeypot_ports.rdp), source = local.internal_src, comment = "Honeypot RDP decoy from internal" },
    { proto = "tcp", dport = tostring(local.honeypot_ports.vnc), source = local.internal_src, comment = "Honeypot VNC decoy from internal" },
    { proto = "tcp", dport = tostring(local.honeypot_ports.redis), source = local.internal_src, comment = "Honeypot Redis decoy from internal" },
    { proto = "tcp", dport = tostring(local.honeypot_ports.git), source = local.internal_src, comment = "Honeypot git decoy from internal" },
    { proto = "tcp", dport = tostring(local.honeypot_ports.http_proxy), source = local.internal_src, comment = "Honeypot HTTP-proxy decoy from internal" },
    { proto = "udp", dport = tostring(local.honeypot_ports.snmp), source = local.internal_src, comment = "Honeypot SNMP decoy from internal" },
    { proto = "udp", dport = tostring(local.honeypot_ports.sip), source = local.internal_src, comment = "Honeypot SIP decoy from internal" },
    { proto = "udp", dport = tostring(local.honeypot_ports.tftp), source = local.internal_src, comment = "Honeypot TFTP decoy from internal" },
    { proto = "udp", dport = tostring(local.honeypot_ports.ntp), source = local.internal_src, comment = "Honeypot NTP decoy from internal" },
  ]

  # The honeypot-notify gateway (apprise-api) inbound surface: just its REST port.
  # Open egress is set on its firewall_options (output_policy ACCEPT) so it can
  # reach external notifiers (Slack/Pushover/ntfy.sh) — same posture as the
  # Mailpit/ntfy notification containers.
  honeypot_notify_services_rules = [
    { proto = "tcp", dport = tostring(local.honeypot_ports.apprise_api), source = local.internal_src, comment = "apprise-api alert gateway from internal" },
  ]
}

# Cluster security groups (defined here rather than security_groups.tf to keep
# that file under the 12 KB size gate).
resource "proxmox_virtual_environment_cluster_firewall_security_group" "honeypot_services" {
  name    = "honeypot-svc"
  comment = "Honeypot decoy services (FTP/Telnet/HTTP/SMB/DB/RDP/VNC/SNMP/SIP/TFTP/NTP/...) — ACCEPT+log from internal so any interaction with a per-VLAN OpenCanary tripwire fires an alert"

  dynamic "rule" {
    for_each = local.honeypot_services_rules
    content {
      type    = "in"
      action  = "ACCEPT"
      proto   = rule.value.proto
      dport   = rule.value.dport
      source  = rule.value.source
      comment = rule.value.comment
    }
  }
}

resource "proxmox_virtual_environment_cluster_firewall_security_group" "honeypot_notify_services" {
  # Proxmox caps cluster security-group names at 18 chars; keep this <= that.
  name    = "honeypot-ntfy-svc"
  comment = "Honeypot alert gateway: apprise-api REST port (${local.honeypot_ports.apprise_api}) from internal networks"

  dynamic "rule" {
    for_each = local.honeypot_notify_services_rules
    content {
      type    = "in"
      action  = "ACCEPT"
      proto   = rule.value.proto
      dport   = rule.value.dport
      source  = rule.value.source
      comment = rule.value.comment
    }
  }
}

resource "proxmox_virtual_environment_firewall_options" "honeypot_container" {
  for_each = var.honeypot_container_ids

  node_name    = var.node_name
  container_id = each.value
  enabled      = local.firewall_defaults.enabled
  input_policy = local.firewall_defaults.input_policy
  # Notify gateway needs the internet (external notifiers); tripwires must not
  # have it (a compromised decoy must not exfiltrate).
  output_policy = contains(keys(var.honeypot_notify_container_ids), each.key) ? "ACCEPT" : local.firewall_defaults.output_policy
  # Decoy interactions are the signal — log inbound at info, not warning.
  log_level_in  = "info"
  log_level_out = local.firewall_defaults.log_level_out

  depends_on = [proxmox_virtual_environment_cluster_firewall.main]
}

resource "proxmox_virtual_environment_firewall_rules" "honeypot_container" {
  for_each = var.honeypot_container_ids

  node_name    = var.node_name
  container_id = each.value

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.internal_access.name
    comment        = "Internal access (SSH, ICMP)"
  }

  # Notify gateway: apprise-api inbound only.
  dynamic "rule" {
    for_each = contains(keys(var.honeypot_notify_container_ids), each.key) ? [1] : []
    content {
      security_group = proxmox_virtual_environment_cluster_firewall_security_group.honeypot_notify_services.name
      comment        = "Honeypot alert gateway (apprise-api)"
    }
  }

  # Tripwires: decoy service surface + internal-only egress (reach notify
  # gateway + HAProxy syslog 519; no internet).
  dynamic "rule" {
    for_each = contains(keys(var.honeypot_notify_container_ids), each.key) ? [] : [1]
    content {
      security_group = proxmox_virtual_environment_cluster_firewall_security_group.honeypot_services.name
      comment        = "Honeypot decoy services (FTP/HTTP/SMB/DB/RDP/SNMP/...)"
    }
  }

  dynamic "rule" {
    for_each = contains(keys(var.honeypot_notify_container_ids), each.key) ? [] : [1]
    content {
      security_group = proxmox_virtual_environment_cluster_firewall_security_group.outbound_internal.name
      comment        = "Outbound to internal only (notify gateway + syslog 519)"
    }
  }

  depends_on = [proxmox_virtual_environment_firewall_options.honeypot_container]
}
