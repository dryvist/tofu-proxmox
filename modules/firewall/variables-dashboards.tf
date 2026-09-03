# Estate-dashboard container-id inputs, split out of variables.tf (which reached
# the shared _file-size 12 KB error threshold) for the same reason
# variables-hermes-ui.tf was split out. Homarr's own input stays in variables.tf;
# these are the two boards added alongside it.
#
# All three boards render their service list from the SAME published ingress
# table, so they are configured once and never drift apart.

variable "homepage_container_ids" {
  description = "Map of Homepage (gethomepage) container names to their IDs (homepage tag). Service-launcher dashboard — inbound homepage_web (3000) from internal; egress internal plus HTTPS/HTTP, because Homepage does not bundle its icon sets and fetches them from a remote CDN at render time."
  type        = map(number)
  default     = {}
}

variable "glance_container_ids" {
  description = "Map of Glance container names to their IDs (glance tag). Dashboard — inbound glance_web (8080) from internal; egress internal plus HTTPS/HTTP for its external feed widgets. Glance ships no authentication of its own, so the Authelia gate on its Traefik route is the only thing in front of it."
  type        = map(number)
  default     = {}
}

variable "status_container_ids" {
  description = "Map of status-guest container names to their IDs (status tag). Hosts Gatus (gatus_web) and Uptime Kuma (uptime_kuma_web) as a Docker-in-LXC compose stack — inbound both ports from internal; egress internal plus HTTPS/HTTP so Gatus can probe public Authelia-gated URLs and pull images."
  type        = map(number)
  default     = {}
}

variable "grafana_container_ids" {
  description = "Map of Grafana observability container names to their IDs (grafana tag). Grafana UI — inbound grafana_web (3000) from internal, Traefik-fronted behind Authelia — plus VictoriaMetrics — inbound victoriametrics (8428) remote_write/datasource from internal; egress internal plus HTTPS/HTTP for container-image pulls at converge."
  type        = map(number)
  default     = {}
}
