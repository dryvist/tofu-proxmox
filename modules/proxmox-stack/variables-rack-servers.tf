# Rack-server variables: cluster identity for 1U/2U servers joining the
# Proxmox cluster (Dell PowerEdge, HPE ProLiant, Supermicro, etc.).
#
# DRY: real values supplied via private RustFS private RustFS deployment object — see
# private RustFS deployment object.example for the placeholder shape. Public repo never
# contains real IPs, MACs, service tags, or hostnames.

variable "rack_servers" {
  description = <<-EOT
    Map of rack servers joining the Proxmox cluster. Keyed by node name
    (chosen by the operator — e.g. "node-a", "node-b"). Real values supplied
    via private RustFS private RustFS deployment object; default is an empty map so plans
    succeed cleanly before any nodes are populated.

    Fields:
      chassis     - Free-form model identifier ("r410", "r710",
                    "dl360-g6", etc.). Not validated against a vendor list so
                    HPE/Supermicro/etc. fit alongside Dell.
      bmc_ip      - Out-of-band management IP (iDRAC on Dell, iLO on HPE,
                    IMM on Lenovo, etc.).
      bmc_mac     - BMC NIC MAC address (dedicated NIC where available).
      service_tag - Vendor service tag, used for inventory + warranty lookup.
      mgmt_ip     - Host OS management IP (PVE web UI, SSH).
  EOT
  type = map(object({
    chassis     = string
    bmc_ip      = string
    bmc_mac     = string
    service_tag = string
    mgmt_ip     = string
  }))
  default   = {}
  sensitive = true

  validation {
    # cidrhost("${ip}/32", 0) returns the same string iff `ip` is a valid IPv4.
    # Catches private RustFS typos cheaply. Error message intentionally omits the value
    # because the variable is sensitive.
    condition = alltrue([
      for k, v in var.rack_servers :
      can(cidrhost("${v.bmc_ip}/32", 0)) && can(cidrhost("${v.mgmt_ip}/32", 0))
    ])
    error_message = "Each rack_servers entry must set bmc_ip and mgmt_ip to a valid IPv4 address."
  }
}
