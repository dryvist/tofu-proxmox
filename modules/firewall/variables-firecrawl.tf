# Firecrawl container-id input, split out of variables.tf (which reached the
# shared _file-size 12 KB error threshold) for the same reason
# variables-hermes-ui.tf and variables-llm-fabric.tf were split out.

variable "firecrawl_container_ids" {
  description = "Map of Firecrawl LXC names to IDs (tag-driven: firecrawl). Self-hosted page-extraction service on the AI VLAN. Its own tag, distinct from the firecrawl-client tag the agent guests carry — a client in this map would be firewalled as a service instance."
  type        = map(number)
  default     = {}
}
