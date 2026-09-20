# Generated guest naming — split from locals.tf so that file stays under the
# shared _file-size workflow's 12 KB limit (locals merge across files in a
# module, so this is a pure relocation with no behavior change).

locals {
  # Every guest name is GENERATED, never declared: <app>-<vm_id>, where <app>
  # is the desired-state map key with any trailing "-<digits>" stripped (so
  # today's keys like "llm-router-1" become app "llm-router"). No hostname/name
  # field is read from deployment.json for this — if the object still carries
  # one it is silently ignored. See docs/GUEST_NAMING.md.
  guest_hostname_containers = {
    for k, v in var.containers : k => "${replace(k, "/-[0-9]+$/", "")}-${v.vm_id}"
  }
  guest_hostname_vms = {
    for k, v in var.vms : k => "${replace(k, "/-[0-9]+$/", "")}-${v.vm_id}"
  }

  # Deterministic, locally-administered MAC per DHCP-first guest. The `02:` prefix
  # marks it locally-administered + unicast (RFC 7042). The remaining 5 octets are
  # a stable digest of the map key, so the MAC is reproducible across rebuilds and
  # plan runs WITHOUT reading provider state. We set it on the NIC explicitly
  # because bpg/proxmox auto-generates a random MAC otherwise and (v0.90+) does not
  # expose it as an output.
  #
  # What this buys, now that nothing reserves an address against it: LEASE
  # STABILITY. The DHCP server keys a lease to the MAC, so a stable MAC means a
  # rebuilt guest comes back on the same address under the same lease-table name.
  # A provider-random MAC would hand every rebuild a new address and a new record.
  # It is no longer a join key into a reservation — there are no reservations for
  # these guests; see the addressing note above.
  #
  # Seeded from the map key, not the generated hostname: the key is the
  # resource address and never changes, so the lease survives a hostname
  # change (guest_hostname_containers above).
  container_mac = {
    for k, v in var.containers : k => format("02:%s:%s:%s:%s:%s",
      substr(md5(k), 0, 2), substr(md5(k), 2, 2),
      substr(md5(k), 4, 2), substr(md5(k), 6, 2),
    substr(md5(k), 8, 2))
  }
  # Reachable address each container advertises to downstream consumers (the
  # ansible_inventory ip field and the Traefik ingress backend). Static guests
  # advertise their derived host IP (CIDR mask stripped); DNS-first guests
  # (dhcp = true) advertise their FQDN {hostname}.{domain} so nothing downstream
  # pins an address the DHCP lease can change — reachable by name regardless of IP.
  container_address = {
    for k, v in var.containers : k => (
      try(v.dhcp, false)
      ? (
        local.guest_domain[v.vlan] != ""
        ? "${local.guest_hostname_containers[k]}.${local.guest_domain[v.vlan]}"
        : local.guest_hostname_containers[k]
      )
      : split("/", local.container_ipv4[k])[0]
    )
  }
}
