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
