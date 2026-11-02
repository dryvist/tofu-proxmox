variable "hatchet_health_ingress_src" {
  description = "Comma-separated ingress proxy addresses allowed to probe the Hatchet engine health listener. Derived from the ingress inventory."
  type        = string
  default     = ""
}
