# grafana tag-filter local — kept out of locals.tf so that file stays under the
# shared _file-size workflow's 12 KB limit (locals merge across files in a
# module, so this is a pure relocation). Same split as locals-homepage.tf /
# locals-glance.tf, whose shape this copies deliberately.

locals {
  # Grafana + VictoriaMetrics observability guest — Grafana web UI on
  # grafana_web (3000, Traefik-fronted, Authelia-gated) and VictoriaMetrics on
  # victoriametrics (8428) receiving Prometheus remote_write from the internal
  # pipeline. modules/firewall opens both from internal only.
  grafana_container_ids = {
    for k, v in var.containers : k => v.vm_id
    if contains(coalesce(try(v.tags, null), []), "grafana")
  }
}
