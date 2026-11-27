variable "splunk_subnet_sources" {
  description = "CIDR sources allowed TCP, UDP, and ICMP access to Splunk VMs."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for source in var.splunk_subnet_sources : can(cidrhost(source, 0))])
    error_message = "Each splunk_subnet_sources entry must be a valid CIDR block."
  }
}

variable "splunk_web_sources" {
  description = "CIDR sources allowed TCP access to Splunk Web (8000); replaces its internal-wide allowance when non-empty."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for source in var.splunk_web_sources : can(cidrhost(source, 0))])
    error_message = "Each splunk_web_sources entry must be a valid CIDR block."
  }
}

variable "splunk_mgmt_sources" {
  description = "CIDR sources allowed TCP access to the Splunk REST API (8089)."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for source in var.splunk_mgmt_sources : can(cidrhost(source, 0))])
    error_message = "Each splunk_mgmt_sources entry must be a valid CIDR block."
  }
}

variable "splunk_hec_sources" {
  description = "CIDR sources allowed TCP access to Splunk HEC (8088); replaces its internal-wide allowance when non-empty."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for source in var.splunk_hec_sources : can(cidrhost(source, 0))])
    error_message = "Each splunk_hec_sources entry must be a valid CIDR block."
  }
}

variable "splunk_forwarding_sources" {
  description = "CIDR sources allowed TCP access to the Splunk forwarding port; replaces its internal-wide allowance when non-empty."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for source in var.splunk_forwarding_sources : can(cidrhost(source, 0))])
    error_message = "Each splunk_forwarding_sources entry must be a valid CIDR block."
  }
}
