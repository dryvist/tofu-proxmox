# Cribl S2S + metrics ports, merged into pipeline_constants.service_ports.
# Split out so constants.tf stays under the shared 12 KB file-size limit.

locals {
  cribl_metrics_ports = {
    # Cribl S2S (TCP-JSON) ingestion port.
    cribl_s2s = 10300
    # Dedicated Cribl S2S receiver for Edge metric events.
    cribl_s2s_metrics = 10360
    # Cribl Stream Prometheus remote_write receiver.
    cribl_prometheus_rw = 9201
  }
}
