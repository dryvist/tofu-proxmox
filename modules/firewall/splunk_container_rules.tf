# Splunk containers.
#
# Extracted from container_rules.tf (alongside the zero-trust rule additions)
# to keep container_rules.tf under the shared _file-size workflow's 12 KB
# error threshold.

resource "proxmox_virtual_environment_firewall_options" "splunk_container" {
  for_each = var.splunk_container_ids

  node_name     = var.node_name
  container_id  = each.value
  enabled       = local.firewall_defaults.enabled
  input_policy  = local.firewall_defaults.input_policy
  output_policy = local.firewall_defaults.output_policy
  log_level_in  = local.firewall_defaults.log_level_in
  log_level_out = local.firewall_defaults.log_level_out

  depends_on = [proxmox_virtual_environment_cluster_firewall.main]
}

resource "proxmox_virtual_environment_firewall_rules" "splunk_container" {
  for_each = var.splunk_container_ids

  node_name    = var.node_name
  container_id = each.value

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.internal_access.name
    comment        = "Internal access (SSH, ICMP)"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.splunk_services.name
    comment        = "Splunk services (Web, HEC, Forwarding)"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.syslog.name
    comment        = "Syslog ingestion"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.splunk_cluster.name
    comment        = "Splunk cluster communication"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.outbound_internal.name
    comment        = "Outbound to internal only"
  }

  # --- zero-trust (staged disabled) ---
  rule {
    enabled = local.zt_enabled
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = tostring(local.svc_ports.splunk_hec)
    source  = join(",", compact([local.zt_src["pipeline"], local.zt_src["siem"]]))
    comment = "ZT: Splunk HEC from pipeline"
  }

  dynamic "rule" {
    for_each = local.zt_src
    content {
      enabled = local.zt_enabled
      type    = "in"
      action  = "ACCEPT"
      proto   = "tcp"
      dport   = tostring(local.svc_ports.splunk_forwarding)
      source  = rule.value
      comment = "ZT: Splunk forwarding (universal forwarders) from ${rule.key}"
    }
  }

  rule {
    enabled = local.zt_enabled
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = tostring(local.svc_ports.splunk_web)
    source  = local.zt_src["mgmt"]
    comment = "ZT: Splunk Web UI (admin plane) from mgmt"
  }

  depends_on = [proxmox_virtual_environment_firewall_options.splunk_container]
}
