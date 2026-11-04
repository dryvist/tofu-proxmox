# Object storage (RustFS) container firewall resources. Extracted from
# container_rules.tf so that file stays under the shared _file-size workflow's
# 12 KB error threshold (same pattern as idrac_rules.tf). S3 API on 9000,
# Console on 9001 — both internal-only via the object-storage-svc group.

resource "proxmox_virtual_environment_firewall_options" "s3_container" {
  for_each = var.s3_container_ids

  node_name     = var.node_name
  container_id  = each.value
  enabled       = local.firewall_defaults.enabled
  input_policy  = local.firewall_defaults.input_policy
  output_policy = local.firewall_defaults.output_policy
  log_level_in  = local.firewall_defaults.log_level_in
  log_level_out = local.firewall_defaults.log_level_out

  # This is a DHCP-first guest (deployment.json dhcp=true) behind DROP in/out
  # policies. Without the firewall's dhcp allow, its own DHCPDISCOVER/OFFER is
  # dropped and it never leases its reserved siem IP. Static-IP firewalled
  # guests don't need this, so it's set here rather than in firewall_defaults.
  dhcp = true

  depends_on = [proxmox_virtual_environment_cluster_firewall.main]
}

resource "proxmox_virtual_environment_firewall_rules" "s3_container" {
  for_each = var.s3_container_ids

  node_name    = var.node_name
  container_id = each.value

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.internal_access.name
    comment        = "Internal access (SSH, ICMP)"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.s3_services.name
    comment        = "Object storage services (TCP/${local.svc_ports.object_storage_s3} S3 API, TCP/${local.svc_ports.object_storage_console} Console)"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.outbound_internal.name
    comment        = "Outbound to internal"
  }

  # TCP 443 outbound. This guest is the only holder of every object it stores,
  # so its buckets are copied to an offsite S3-compatible target on a schedule
  # (ansible-proxmox-apps roles/object_storage). That copy is the sole reason
  # for this grant: without it the guest reaches nothing off-network and the
  # timers fail every run. Inbound is unchanged — still internal-only.
  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.outbound_https.name
    comment        = "Outbound HTTPS for scheduled offsite bucket copies"
  }

  depends_on = [proxmox_virtual_environment_firewall_options.s3_container]
}
