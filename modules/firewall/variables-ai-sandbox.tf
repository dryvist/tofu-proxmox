# AI sandbox VM inputs, split out of variables-guest-sets.tf (shared
# _file-size 12 KB gate) for the same reason variables-hermes-ui.tf was.

variable "ai_sandbox_vm_ids" {
  description = "Map of agent-sandbox VM names to IDs (tag-driven: agent-sandbox). Docker host that runs untrusted agent CLIs in ephemeral containers — inbound SSH/ICMP from internal (Ansible converge) + HTTPS from the ingress Traefik instances only; egress to internal DNS/NTP/OpenBao/log ingest plus 80/443 to any, narrowed to an allowlist by the on-host egress proxy and an on-host container-egress filter."
  type        = map(number)
  default     = {}
}

variable "ai_sandbox_ingress_src" {
  description = "Comma-separated ingress Traefik addresses allowed to reach the agent-sandbox VM's HTTPS port. Derived from the inventory in root locals. Empty renders no inbound rule (a sourceless rule would accept the port from anywhere)."
  type        = string
  default     = ""
}
