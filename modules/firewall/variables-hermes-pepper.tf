variable "hermes_pepper_container_ids" {
  description = "Map of Hermes guest names to IDs selected by the hermes-pepper tag. Uses the shared ai-proxied egress profile."
  type        = map(number)
  default     = {}
}
