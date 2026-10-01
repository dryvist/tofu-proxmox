# Guest naming — the ONE place a hostname/name is derived, consumed by every
# container and VM path (regular desired-state entries, the openbao cluster
# generator, and the per-node service generator — see root main.tf and
# locals-node-services.tf, which both key their generated maps on
# "<app>-<vm_id>" and no longer set hostname/name themselves).
#
# Rule: a desired-state entry that DECLARES hostname/name keeps that value
# until its own rename wave — no guard, no exception list, just "declared
# beats generated". An entry that OMITS it gets the generated form. This is
# how a new guest is generated-only while an existing one is untouched: it is
# a property of the desired-state object (declared vs. omitted), not a
# hand-maintained list here. See docs/GUEST_NAMING.md.
#
# <app> is the desired-state map key with any trailing "-<digits>" stripped,
# so a key like "openbao-110001" (already "<app>-<vm_id>") round-trips to the
# same string, and a key like "llm-router-1" generates "llm-router-<vm_id>".
locals {
  guest_hostname_containers = {
    for k, v in var.containers : k => coalesce(v.hostname, "${replace(k, "/-[0-9]+$/", "")}-${v.vm_id}")
  }
  guest_hostname_vms = {
    for k, v in var.vms : k => coalesce(v.name, "${replace(k, "/-[0-9]+$/", "")}-${v.vm_id}")
  }

  # Deterministic, locally-administered MAC per DHCP-first guest. The `02:` prefix
  # marks it locally-administered + unicast (RFC 7042). The remaining 5 octets are
  # a stable digest of the (resolved) hostname, so the MAC is reproducible across
  # rebuilds and plan runs WITHOUT reading provider state. We set it on the NIC
  # explicitly because bpg/proxmox auto-generates a random MAC otherwise and
  # (v0.90+) does not expose it as an output.
  #
  # What this buys, now that nothing reserves an address against it: LEASE
  # STABILITY. The DHCP server keys a lease to the MAC, so a stable MAC means a
  # rebuilt guest comes back on the same address under the same lease-table name.
  # A provider-random MAC would hand every rebuild a new address and a new record.
  # It is no longer a join key into a reservation — there are no reservations for
  # these guests; see locals.tf's addressing note.
  container_mac = {
    for k, v in var.containers : k => format("02:%s:%s:%s:%s:%s",
      substr(md5(local.guest_hostname_containers[k]), 0, 2), substr(md5(local.guest_hostname_containers[k]), 2, 2),
      substr(md5(local.guest_hostname_containers[k]), 4, 2), substr(md5(local.guest_hostname_containers[k]), 6, 2),
    substr(md5(local.guest_hostname_containers[k]), 8, 2))
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
