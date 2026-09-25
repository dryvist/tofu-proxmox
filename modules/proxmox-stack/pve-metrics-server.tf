# Registers Proxmox VE's native External Metric Server, pushing cluster,
# node, guest and storage stats to Cribl Stream's Metrics source over the
# Graphite wire protocol (TCP, for delivery reliability over UDP).
resource "proxmox_metrics_server" "cribl_pve_metrics" {
  name           = "cribl-pve-metrics"
  server         = "cribl-pve-metrics.pve.${var.domain}"
  port           = local.pipeline_constants.service_ports.cribl_pve_metrics
  type           = "graphite"
  graphite_proto = "tcp"
}
