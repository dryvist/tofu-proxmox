locals {
  splunk_vm_service_sources_configured = anytrue([
    length(var.splunk_web_sources) > 0,
    length(var.splunk_hec_sources) > 0,
    length(var.splunk_forwarding_sources) > 0,
    length(var.splunk_mgmt_sources) > 0,
  ])

  splunk_vm_point_to_point_rules = concat(
    length(var.splunk_subnet_sources) > 0 ? [
      { proto = "tcp", dport = null, source = join(",", var.splunk_subnet_sources), comment = "Splunk subnet TCP from configured CIDRs" },
      { proto = "udp", dport = null, source = join(",", var.splunk_subnet_sources), comment = "Splunk subnet UDP from configured CIDRs" },
      { proto = "icmp", dport = null, source = join(",", var.splunk_subnet_sources), comment = "Splunk subnet ICMP from configured CIDRs" },
    ] : [],
    local.splunk_vm_service_sources_configured ? [
      {
        proto   = "tcp"
        dport   = tostring(local.svc_ports.splunk_web)
        source  = length(var.splunk_web_sources) > 0 ? join(",", var.splunk_web_sources) : local.internal_src
        comment = "Splunk Web (TCP ${local.svc_ports.splunk_web}) from configured or existing internal sources"
      },
      {
        proto   = "tcp"
        dport   = tostring(local.svc_ports.splunk_hec)
        source  = length(var.splunk_hec_sources) > 0 ? join(",", var.splunk_hec_sources) : local.internal_src
        comment = "Splunk HEC (TCP ${local.svc_ports.splunk_hec}) from configured or existing internal sources"
      },
      {
        proto   = "tcp"
        dport   = tostring(local.svc_ports.splunk_forwarding)
        source  = length(var.splunk_forwarding_sources) > 0 ? join(",", var.splunk_forwarding_sources) : local.internal_src
        comment = "Splunk Forwarding (TCP ${local.svc_ports.splunk_forwarding}) from configured or existing internal sources"
      },
    ] : [],
    length(var.splunk_mgmt_sources) > 0 ? [
      {
        proto   = "tcp"
        dport   = tostring(local.svc_ports.splunk_mgmt)
        source  = join(",", var.splunk_mgmt_sources)
        comment = "Splunk REST API (TCP ${local.svc_ports.splunk_mgmt}) from configured CIDRs"
      },
    ] : []
  )
}
