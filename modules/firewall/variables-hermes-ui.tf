# hermes-ui container-id input, split out of variables.tf (which reached the
# shared _file-size 12 KB error threshold) for the same reason
# variables-llm-fabric.tf was split out.

variable "hermes_ui_container_ids" {
  description = "Map of hermes-ui LXC names to IDs (tag-driven: hermes-ui). Companion web UI guest for the Hermes agent, own tag so its egress can be tightened later without touching the hermes-agent profile."
  type        = map(number)
  default     = {}
}
