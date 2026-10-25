variable "workstations" {
  description = "Non-secret workstation identities keyed by workstation name, with a DNS host and consumer role labels."
  type = map(object({
    host  = string
    roles = list(string)
  }))
  default = {}
}
