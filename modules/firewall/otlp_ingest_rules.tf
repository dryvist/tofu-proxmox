# OTLP trace-ingest security group.
#
# The collector tier that terminates OTLP moved once already, and the firewall
# accept did not move with it. That is silent in both directions: an OTLP
# exporter reports a failed batch only in its own service log, and a listener
# nothing reaches has nothing to log — so the destination index simply stays
# empty while every component reports healthy.
#
# Attached to the Cribl Stream containers (container_rules.tf), which is where
# the in_otel listener now runs.
#
# DRY: ports come from var.pipeline_constants.service_ports, the same source
# the collector role and the ingress backends read, so a port change moves the
# listener, the ingress and this accept together.
locals {
  otlp_ingest_ports = [
    local.svc_ports.otel_traces_http,
    local.svc_ports.otel_traces_grpc,
  ]
}

resource "proxmox_virtual_environment_cluster_firewall_security_group" "otlp_ingest" {
  name    = "otlp-ingest"
  comment = "OTLP trace ingest from internal networks to the Cribl Stream in_otel listener"

  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = join(",", [for p in local.otlp_ingest_ports : tostring(p)])
    source  = local.internal_src
    comment = "OTLP traces (HTTP + gRPC) from internal"
  }
}
