# herdr firewall inputs (tag-driven; see modules/proxmox-stack/locals-herdr.tf).
#
# Declared as two sets rather than one because an untagged guest gets the NIC's
# firewall flag with no options and no rules — a state invisible in a plan diff.
# Every herdr guest therefore carries a tag that lands it in exactly one of
# these.

variable "herdr_container_ids" {
  description = "Map of herdr runtime LXC names to IDs (tag-driven: herdr, excluding the herdr-ui client tag). Runs the agent panes and the Slack bridge plugin, so it needs the broad outbound HTTPS the CLIs require plus Slack's outbound WebSocket."
  type        = map(number)
  default     = {}
}

variable "herdr_client_container_ids" {
  description = "Map of herdr client LXC names to IDs (tag-driven: herdr-ui). Reaches the runtime over SSH, deliberately without the runtime's egress."
  type        = map(number)
  default     = {}
}
