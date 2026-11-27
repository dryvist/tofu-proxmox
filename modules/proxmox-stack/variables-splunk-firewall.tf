variable "splunk_subnet_sources" {
  description = "CIDR sources allowed all TCP, UDP, and ICMP access to Splunk VMs."
  type        = list(string)
  default     = []
}

variable "splunk_web_sources" {
  description = "CIDR sources allowed TCP access to Splunk Web (8000)."
  type        = list(string)
  default     = []
}

variable "splunk_mgmt_sources" {
  description = "CIDR sources allowed TCP access to the Splunk REST API (8089)."
  type        = list(string)
  default     = []
}

variable "splunk_hec_sources" {
  description = "CIDR sources allowed TCP access to Splunk HEC (8088)."
  type        = list(string)
  default     = []
}

variable "splunk_forwarding_sources" {
  description = "CIDR sources allowed TCP access to the Splunk forwarding port."
  type        = list(string)
  default     = []
}
