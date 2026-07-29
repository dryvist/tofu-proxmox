# Ingress HA (keepalived VRRP virtual IP) derivations.
#
# Traefik is no longer a single-node SPOF: every LXC tagged "ingress" runs an
# identical Traefik instance, and keepalived (ansible-proxmox-apps) floats ONE
# virtual IP across them (unicast VRRP). DNS points every fronted service at this
# VIP (see the technitium_dns role), so a node loss migrates the VIP to a
# surviving Traefik with zero manual action. Both instances always run and each
# fetches its own ACME cert independently (no shared acme.json state).
#
# Extracted from ingress.tf so that file stays under the shared _file-size
# workflow's 12 KB error threshold; locals merge across files in the module
# (same split pattern as locals-honeypot.tf / locals-vm-network.tf).
locals {
  # ingress_vip_host: the reserved HOST OCTET for the VIP inside the ingress
  # VLAN. It is NOT a literal IP — the address is derived via cidrhost() from the
  # private RustFS network_cidrs, so the real subnet never appears in-repo.
  #
  # Octets .1-.19 are reserved in EVERY VLAN for network and core services, and
  # the same octet means the same thing in each. Within that block the ingress
  # instances take the .7/.8 pair (odd primary, even hot backup) and the
  # floating VIP sits alongside them at .9, so an address is self-describing
  # without a per-VLAN lookup table.
  #
  # .2 is NOT available: it is reserved for the network controller. This local
  # previously resolved there, which collided with that reservation.
  ingress_vip_host = 9
  ingress_container_keys = sort([
    for k, v in var.containers : k
    if contains(coalesce(try(v.tags, null), []), "ingress")
  ])
  # VLAN taken from the ingress containers themselves, so the VIP follows a VLAN
  # move automatically instead of pinning a hardcoded key. Falls back to "mgmt"
  # only when no ingress container is deployed (VIP then resolves to "").
  ingress_vlan = try(var.containers[local.ingress_container_keys[0]].vlan, "mgmt")
  # A VIP is only synthesized with >= 2 ingress instances. With a single (or zero)
  # ingress node keepalived never binds the VIP, so publishing it would black-hole
  # DNS (technitium points fronted services at an unbound address). Empty here lets
  # the technitium_dns role fall back to the single Traefik host's own IP.
  ingress_vip = length(local.ingress_container_keys) > 1 ? nonsensitive(
    cidrhost(var.network_cidrs[local.ingress_vlan], local.ingress_vip_host)
  ) : ""
  # Advertised address of each ingress instance — the keepalived unicast_peer
  # list. Same container_address shape (static host IP / DNS-first FQDN) as every
  # other backend pool.
  ingress_hosts = [for k in local.ingress_container_keys : local.container_address[k]]
}
