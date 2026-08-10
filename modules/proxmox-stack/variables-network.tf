# Network variables: bridge, per-VLAN addressing, and firewall network ranges

variable "bridge" {
  description = "Network bridge for Splunk VM network interface"
  type        = string
  default     = "vmbr0"
  validation {
    condition     = length(var.bridge) > 0
    error_message = "Bridge name cannot be empty."
  }
}

# Per-VLAN network CIDRs (SENSITIVE — real subnets are not committed).
# Canonical source is OpenBao `NETWORK_CIDR_<KEY>` (network-form CIDRs such as
# 192.168.20.0/24), injected by native root configuration and shared one-way with
# tofu-unifi. No default: a missing key fails loudly instead of silently
# selecting the wrong subnet. Each guest's IP is derived as
# cidrhost(network_cidrs[guest.vlan], guest.vm_id) and its gateway as
# cidrhost(network_cidrs[guest.vlan], 1) — zero literal IP octets in this repo.
variable "network_cidrs" {
  description = "Map of VLAN name => network-form CIDR (e.g. siem => 192.168.20.0/24). Sourced from OpenBao NETWORK_CIDR_* (sensitive). IPs are derived via cidrhost(cidr, vm_id); masks are taken from the CIDR itself."
  type        = map(string)
  sensitive   = true

  validation {
    condition = alltrue([
      for k, c in var.network_cidrs : can(cidrhost(c, 1))
    ])
    error_message = "Each network_cidrs entry must be a valid network-form CIDR (e.g. 192.168.20.0/24)."
  }
}

# VLAN name => 802.1Q tag id. Non-secret topology structure — adapt VLAN IDs
# to match your own network design. See deployment.json.example for example values.
# Drives each guest NIC's vlan_id = vlan_ids[guest.vlan].
variable "vlan_ids" {
  description = "Map of VLAN name => 802.1Q VLAN id (non-secret topology). Single source of truth: example network CIDRs are derived as 192.168.<vlan_id>.0/24, so the third octet always matches the VLAN id. Override per your own topology."
  type        = map(number)
  default = {
    lan_main  = 1
    dns       = 2
    mgmt      = 5
    bmc       = 8
    compute   = 10
    siem      = 40
    pipeline  = 25
    data      = 30
    ai        = 50
    apps      = 60
    media_svc = 70
    homeauto  = 80
    nonprod   = 90
  }
}

# VLAN keys whose subnets a VDI guest must keep reaching over its own LAN when a
# VPN client inside the guest installs a default route.
#
# A full-tunnel client (FortiClient, and every other one) replaces the guest's
# default route, so the guest's REPLY packets to anything off its own subnet go
# into the tunnel and die. Inbound RDP still arrives; the session drops anyway.
# A more-specific persistent route per preserved subnet outranks the tunnel's
# /0 (or its /1 pair) and keeps those networks on the LAN.
#
# Deliberately a short opt-in list rather than every key in network_cidrs:
# routing the whole estate past the tunnel would break the VDI's purpose the
# moment a corporate network behind the VPN overlaps an estate VLAN. List only
# what must survive — the operator's own subnet and the Ansible controller's,
# without which no converge can reach the guest while the VPN is up.
#
# Empty default = no routes published = the consuming role no-ops.
variable "vdi_preserved_vlans" {
  description = "VLAN keys (into network_cidrs) whose subnets VDI guests keep reaching over the LAN instead of a guest-side VPN tunnel. Published to the inventory as vdi_preserved_cidrs. Empty disables the behaviour."
  type        = list(string)
  default     = []
}
