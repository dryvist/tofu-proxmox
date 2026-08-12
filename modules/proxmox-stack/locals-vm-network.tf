# Per-VM addressing locals — extracted from locals.tf so that file stays under
# the shared _file-size workflow's 12 KB limit (locals merge across files in a
# module, so this is a pure relocation with no behavior change). Mirrors the
# container_* addressing locals in locals.tf.

locals {
  # Per-VM IPv4/gateway, same DRY + short-circuit rules as containers, so a VM
  # can carry a 6-7-digit positional VMID (which overflows the /24 host space)
  # by going DHCP-first (dhcp = true) or pinning a static ipv4_address. The
  # cidrhost derive branch is reached ONLY when neither is set (legacy ≤254 ids),
  # exactly mirroring container_ipv4 — see the extended note in that block.
  vm_ipv4 = {
    for k, v in var.vms : k => (
      try(v.dhcp, false) ? "dhcp" : (
        try(v.ip_config.ipv4_address, null) != null
        ? nonsensitive(v.ip_config.ipv4_address)
        : nonsensitive("${cidrhost(var.network_cidrs[v.vlan], v.vm_id)}/${split("/", var.network_cidrs[v.vlan])[1]}")
      )
    )
  }
  vm_gateway = {
    for k, v in var.vms : k => (
      try(v.dhcp, false) ? null : nonsensitive(cidrhost(var.network_cidrs[v.vlan], 1))
    )
  }

  # Deterministic MAC + advertised address for DHCP-first VMs — same shape and
  # same rationale as the container_* locals in locals.tf: the MAC is stable so
  # the lease (and therefore the address and the lease-table DNS name) survives a
  # rebuild. Nothing reserves an address against it.
  vm_mac = {
    for k, v in var.vms : k => format("02:%s:%s:%s:%s:%s",
      substr(md5(v.name), 0, 2), substr(md5(v.name), 2, 2),
      substr(md5(v.name), 4, 2), substr(md5(v.name), 6, 2),
    substr(md5(v.name), 8, 2))
  }
  vm_address = {
    for k, v in var.vms : k => (
      try(v.dhcp, false)
      ? (
        local.guest_domain[v.vlan] != ""
        ? "${v.name}.${local.guest_domain[v.vlan]}"
        : v.name
      )
      : split("/", local.vm_ipv4[k])[0]
    )
  }
}

locals {
  # The gateway of the VLAN a guest sits on, independent of how the guest gets
  # its address. Distinct from vm_gateway above, which is null for DHCP-first
  # guests because cloud-init must not pin a static gateway on them.
  #
  # Published for guests whose own view of "the gateway" cannot be trusted: a
  # VPN client inside a guest installs its own default route, so anything asking
  # the OS which gateway to use gets the tunnel's. The VLAN's gateway is the .1
  # of its CIDR whether the guest was addressed statically or by lease, and it
  # is the same value DHCP hands out — the estate is DHCP-first by design, so
  # deriving this only for static guests would exclude nearly all of them.
  vm_lan_gateway = {
    for k, v in var.vms : k => nonsensitive(cidrhost(var.network_cidrs[v.vlan], 1))
  }
}
