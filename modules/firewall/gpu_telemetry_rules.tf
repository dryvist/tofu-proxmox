# DCGM exporter scrape access is limited to NVIDIA GPU passthrough guests.
# Attached by the llm_fast_container and llm_classify_container rule resources
# (llm_fabric_rules.tf), which own those guests' complete rule lists.
resource "proxmox_virtual_environment_cluster_firewall_security_group" "gpu_telemetry" {
  count = var.prometheus_scraper_trusted_src == "" ? 0 : 1

  name    = "gpu-telemetry"
  comment = "NVIDIA DCGM exporter metrics from the Prometheus scraper"

  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = tostring(local.svc_ports.dcgm_exporter)
    source  = var.prometheus_scraper_trusted_src
    comment = "NVIDIA DCGM exporter scrape from the Prometheus scraper"
  }
}
