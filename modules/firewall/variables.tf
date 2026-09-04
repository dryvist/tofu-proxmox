variable "node_name" {
  description = "Proxmox node name"
  type        = string
}

variable "management_network" {
  description = "CIDR of management network for SSH/Web access. Configure in terraform.tfvars for your environment."
  type        = string
  # No default - must be specified in .tfvars for environment-specific configuration
}

variable "ai_network" {
  description = "CIDR of the AI VLAN — source scope for the Cribl Edge OTLP ingest (only AI-orchestration apps emit OpenTelemetry). Derived from the OpenBao-sourced network_cidrs map in root locals; never committed."
  type        = string
}

variable "splunk_network" {
  description = "Comma-separated list of Splunk node IPs for cluster communication. Configure in terraform.tfvars for your environment."
  type        = string
  # No default - must be specified in .tfvars for environment-specific configuration
}

variable "pipeline_constants" {
  description = "Single source of truth for service/syslog/netflow/notification/vector-db ports. Sourced from root locals.pipeline_constants so port literals stay defined exactly once across the whole repo."
  type = object({
    service_ports = map(number)
    syslog_ports  = map(number)
    syslog_port_map = map(object({
      standard   = number
      high       = number
      index      = string
      sourcetype = string
    }))
    netflow_ports      = map(number)
    notification_ports = map(number)
    vector_db_ports    = map(number)
    memory_ports       = map(number)
    extract_ports      = map(number)
    honeypot_ports     = map(number)
    ai_log_ports       = map(number)
    media_ports        = map(number)
    iac_platform_ports = map(number)
  })
}

variable "network_cidrs" {
  description = "VLAN key => network-form CIDR, for per-source-VLAN zero-trust rule scoping (staged disabled). Resolved nonsensitive in the root; a single subnet range is not independently secret."
  type        = map(string)
  default     = {}
}

variable "internal_networks" {
  description = "Internal CIDRs allowed through guest firewalls (SSH, service ports). No default — the real ranges come from OpenBao via the root module and are never committed."
  type        = list(string)

  validation {
    condition     = length(var.internal_networks) > 0
    error_message = "internal_networks must contain at least one CIDR — cannot generate firewall rules with no source networks."
  }

  validation {
    condition = alltrue([
      for net in var.internal_networks :
      can(cidrnetmask(net))
    ])
    error_message = "Each internal_networks entry must be a valid CIDR block, for example 192.168.0.0/16."
  }
}

variable "rdp_vm_ids" {
  description = "Map of VM IDs for RDP-enabled virtual machines"
  type        = map(number)
  default     = {}
}
