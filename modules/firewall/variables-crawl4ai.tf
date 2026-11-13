variable "crawl4ai_container_ids" {
  description = "Map of Crawl4AI LXC names to IDs (tag-driven: crawl4ai). The dedicated API security group allows the API port from the AI VLAN ingress source."
  type        = map(number)
  default     = {}
}
