# Registers Proxmox VE's native External Metric Server, pushing cluster,
# node, guest and storage stats to Cribl Stream's Metrics source over the
# Graphite wire protocol (TCP, for delivery reliability over UDP).
#
# The target is the HAProxy guest's own FQDN, not a "*.pve" ingress vhost —
# those are HTTP-only Traefik routes and can't carry a raw TCP Graphite
# stream. Picks the first HAProxy guest deterministically (sorted key) and
# plans nothing when the estate has none, so this never targets a name with
# no DNS record.
locals {
  pve_metrics_haproxy_key = try(sort(keys(local.haproxy_container_ids))[0], null)
}

resource "proxmox_metrics_server" "cribl_pve_metrics" {
  count = length(local.haproxy_container_ids) > 0 ? 1 : 0

  name           = "cribl-pve-metrics"
  server         = "${var.containers[local.pve_metrics_haproxy_key].hostname}.${var.domain}"
  port           = local.pipeline_constants.service_ports.cribl_pve_metrics
  type           = "graphite"
  graphite_proto = "tcp"
}
