variable "splunk_node_name" {
  description = "Fallback Proxmox node for Splunk VM firewall resources; defaults to node_name when unset."
  type        = string
  default     = ""
}

variable "splunk_vm_nodes" {
  description = "Map of Splunk VM names to their actual Proxmox nodes. Entries override splunk_node_name for guests with separate placement."
  type        = map(string)
  default     = {}
}
