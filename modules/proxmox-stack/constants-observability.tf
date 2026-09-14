# Observability / security data-plane ports — one cohesive family kept out of
# constants.tf so that file stays under the shared _file-size 12 KB gate and
# this file can grow with the observability estate (Splunk, Cribl pipeline,
# Grafana/VictoriaMetrics, network-quality probes, the monitoring exporters,
# and the Elastic Stack). Merged into pipeline_constants.service_ports by
# constants.tf; locals merge across files in the module, so consumers still see
# one flat service_ports map and nothing about the split is visible in the
# published inventory.
#
# Split reason: the observability family was the largest single block in
# constants.tf. Moving it here keeps BOTH files comfortably under the gate
# (not a one-off "constants-elastic" file — every observability/security port
# lives together, exactly where a future observability port belongs).
locals {
  observability_ports = {
    # --- Logging / SIEM data plane -------------------------------------------
    splunk_web        = 8000
    splunk_hec        = 8088
    splunk_mgmt       = 8089
    splunk_forwarding = 9997
    cribl_edge_api    = 9420
    cribl_stream_api  = 9000
    # Cribl-to-Cribl (S2S/TCP-JSON) ingestion: remote Edge nodes -> HAProxy -> Stream
    cribl_s2s = 10300
    # Cribl Stream Prometheus remote_write receiver (internal-only; no Traefik/DNS)
    cribl_prometheus_rw = 9201

    # --- Metrics / dashboards ------------------------------------------------
    prometheus_web = 9090
    # Grafana + VictoriaMetrics observability guest (grafana tag):
    # grafana_web is the Traefik-fronted UI; victoriametrics receives
    # Prometheus remote_write from the pipeline (internal-only).
    grafana_web     = 3000
    victoriametrics = 8428
    # ClickHouse (clickhouse + observability tags) — dedicated OLAP store for
    # the observability stack. clickhouse_http = HTTP query interface;
    # clickhouse_native = the native TCP client/replication protocol.
    clickhouse_http   = 8123
    clickhouse_native = 9000

    # --- LLM observability (Langfuse + Arize Phoenix) ------------------------
    langfuse_web = 3000
    # Arize Phoenix (LLM observability — traces/evals), the Langfuse sibling on
    # [ADDRESS] VLAN. phoenix_web serves the UI plus the OTLP/HTTP ingest path
    # (/v1/traces); phoenix_grpc is the OTLP/gRPC ingest, internal only;
    # phoenix_metrics is the Prometheus /metrics endpoint, scraped directly and
    # never Traefik-fronted.
    phoenix_web     = 6006
    phoenix_grpc    = 4317
    phoenix_metrics = 9090

    # --- OpenTelemetry ingest -------------------------------------------------
    # OpenTelemetry ingest on Cribl Edge — native OTLP sources, one port per
    # signal type (gRPC/HTTP) so [ADDRESS] routes by type without inspecting payload.
    # AI orchestration apps (OpenLLMetry) emit here; [ADDRESS] forks to Langfuse +
    # Splunk. Standalone sources, unrelated to the cc-edge-copilot-otel pack.
    otel_traces_grpc  = 4317
    otel_traces_http  = 4318
    otel_metrics_grpc = 4327
    otel_metrics_http = 4328
    otel_logs_grpc    = 4337
    otel_logs_http    = 4338

    # --- Network-quality monitoring (Prometheus-native stack — see docs/SMOKEPING.md):
    #   smokeping_web      — SmokePing RRD/CGI UI (optional, fronted by Traefik)
    #   speedtest_exporter — throughput (Mbps) exporter, scraped by Prometheus
    #   smokeping_prober   — SuperQ ICMP/UDP latency-distribution histograms (system of record)
    #   blackbox_exporter  — DNS / HTTP(S) / TLS / TCP probes + reachability [ADDRESS]
    #   atlas_exporter     — RIPE Atlas outside-in results (external vantage)
    #   irtt               — isochronous UDP RTT/jitter server (real RFC-3393 jitter / MOS)
    smokeping_web      = 80
    speedtest_exporter = 9798
    smokeping_prober   = 9374
    blackbox_exporter  = 9115
    atlas_exporter     = 9400
    irtt               = 2112
    # node_exporter on the Proxmox hosts (host metrics -> siem Cribl Edge scrape)
    node_exporter = 9100
    # Per-uplink network diagnosis (CT netmon-*, mgmt VLAN, Docker-in-LXC): the
    # satellite gRPC exporter scraped by each prober's [ADDRESS], alongside DOCSIS
    # modem SNMP and native active probes. Pushes to [ADDRESS] -> Splunk
    # netmon_metrics index. See docs/NETWORK_DIAGNOSIS.md.
    satellite_exporter = 9817

    # --- Elastic Stack (elastic tag, two-node hot/hot cluster) --------------
    # elastic_http = REST/API/data-plane (internal only; Cribl + app clients
    # reach it directly, never via Traefik). elastic_transport = node-to-node
    # protocol (9300) between the two cluster peers — opened only between the
    # elastic guests. kibana_web = the Traefik-fronted browser UI, pooled.
    elastic_http      = 9200
    elastic_transport = 9300
    kibana_web        = 5601
  }
}
