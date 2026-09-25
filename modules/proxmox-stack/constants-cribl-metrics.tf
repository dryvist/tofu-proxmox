# Cribl S2S + metrics ports, merged into pipeline_constants.service_ports by
# constants.tf.
#
# Split into its own file so constants.tf stays under the shared _file-size
# 12 KB error threshold — the same reason ai_log_ports and dashboard_ports
# live beside it. Locals merge across files in the module, so downstream
# consumers still see one flat service_ports map and nothing about the split
# is visible in the published inventory.

locals {
  cribl_metrics_ports = {
    # Cribl-to-Cribl (S2S/TCP-JSON) ingestion: remote Edge nodes -> HAProxy -> Stream
    cribl_s2s = 10300
    # Dedicated S2S receiver for Edge host/GPU metric events (remote Edge ->
    # HAProxy -> Stream -> victoriametrics_rw). Split out from cribl_s2s:
    # Cribl best practice is a dedicated port per source so routing is by
    # listener, not payload inspection — same rationale as ai_log_ports
    # (constants-ai-log.tf). Splunk already receives these events directly
    # from Edge's own HEC output (os_metrics index); this port exists only
    # to also reach victoriametrics_rw.
    cribl_s2s_metrics = 10360
    # Cribl Stream Prometheus remote_write receiver (internal-only; no Traefik/DNS)
    cribl_prometheus_rw = 9201
  }
}
