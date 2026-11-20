variable "next_ai_drawio_container_ids" {
  description = "Docker AI containers with Next AI Draw.io enabled; the service group is attached additively to their existing AI orchestration firewall rules."
  type        = map(number)
  default     = {}
}

variable "next_ai_drawio_ingress_src" {
  description = "Comma-separated ingress addresses allowed to reach the Next AI Draw.io web listener."
  type        = string
  default     = ""
}

variable "next_ai_drawio_mcp_src" {
  description = "Comma-separated LiteLLM router addresses allowed to reach the Next AI Draw.io MCP listener."
  type        = string
  default     = ""
}
