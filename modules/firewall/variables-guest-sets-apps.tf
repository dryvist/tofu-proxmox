variable "youtrack_container_ids" {
  description = "Map of YouTrack container names to their IDs (youtrack tag). Issue tracker — inbound youtrack_web (8080) from internal; egress mirrors vikunja (outbound internal, HTTPS, HTTP)."
  type        = map(number)
  default     = {}
}

variable "leantime_container_ids" {
  description = "Map of Leantime container names to their IDs (leantime tag). Native PHP project-management app — inbound leantime_web (80) from internal; egress mirrors vikunja (outbound internal, HTTPS, HTTP)."
  type        = map(number)
  default     = {}
}
