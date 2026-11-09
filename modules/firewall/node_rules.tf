# =============================================================================
# Node-Level (Proxmox Host) Firewall Rules
# =============================================================================

# Enable the host-level firewall on the Proxmox node itself. Without this,
# node-level rules below are configured but never evaluated. The cluster
# firewall (main.tf) defaults to ACCEPT input/output, so node-scoped rules
# only ADD positive ACCEPT entries — there is no risk of SSH/web-UI lockout
# from this resource. The bpg/proxmox node-firewall resource has no
# input/output policy fields (those exist only at cluster, VM, and container
# scopes); the cluster-level ACCEPT policy already supplies the default.
resource "proxmox_node_firewall" "node" {
  node_name = var.node_name
  enabled   = true

  depends_on = [proxmox_virtual_environment_cluster_firewall.main]
}

# Apply host-level rules to the Proxmox node itself (no vm_id / container_id).
# Used for services running on the Proxmox host — e.g. chrony serving NTP to
# internal VMs/containers (paired with ansible-proxmox NTP server role).
resource "proxmox_virtual_environment_firewall_rules" "node" {
  node_name = var.node_name

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.ntp_server.name
    comment        = "NTP server (UDP/123, chrony on Proxmox host)"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.node_exporter.name
    comment        = "node_exporter/zfs_exporter host metrics (TCP/9100, TCP/9134) scraped by siem-VLAN Cribl Edge"
  }

  depends_on = [proxmox_node_firewall.node]
}

resource "proxmox_virtual_environment_cluster_firewall_security_group" "node_exporter" {
  name    = "node-exporter"
  comment = "Prometheus node_exporter (TCP 9100) + zfs_exporter (TCP 9134) on the Proxmox hosts, scraped by the siem-VLAN Cribl Edge prometheus input (paired with the ansible-proxmox node_exporter role)"

  dynamic "rule" {
    for_each = local.node_exporter_rules
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
