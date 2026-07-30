# Local values for common computed expressions
locals {
  # DRY per-VLAN Network Configuration - Single Source of Truth.
  # Every guest IP is derived from its VLAN's CIDR (network-form, from OpenBao)
  # and its VM ID: cidrhost(network_cidrs[vlan], vm_id). The gateway is the .1
  # host of that same subnet. Masks come from the CIDR itself, so this repo
  # holds zero literal IP octets.
  #
  # var.network_cidrs is `sensitive` so the full subnet map never leaks via a
  # stray `tofu output`/log. Individual resolved values below are wrapped in
  # nonsensitive(): a single host address (<vlan subnet>.<vmid>) or a guest's
  # own gateway is not independently secret, and these must flow into the
  # ansible_inventory output and module inputs (which are non-sensitive),
  # exactly as the tofu-unifi reference resolves its OpenBao CIDRs.

  # Splunk lives on the siem VLAN (per network/architecture.md). The siem CIDR
  # is the only VLAN referenced by name here; all other guests resolve via their
  # own `vlan` field below.
  splunk_derived_ip      = nonsensitive("${cidrhost(var.network_cidrs["siem"], var.splunk_vm_id)}/${split("/", var.network_cidrs["siem"])[1]}")
  splunk_network_gateway = nonsensitive(cidrhost(var.network_cidrs["siem"], 1))

  # Per-guest IPv4 (CIDR notation) and gateway, keyed by resource name. IP is
  # cidrhost(<guest VLAN CIDR>, vm_id); gateway is the .1 of that subnet.
  # A container MAY pin a static ipv4_address (CIDR form, e.g. "192.168.5.10/24") to
  # override the vm_id-derived address — for fixed low-number hosts (e.g. a DNS server
  # at .10) whose address must not follow the vm_id. Otherwise derived as usual.
  # DNS-first guests (dhcp = true) resolve to the literal "dhcp" instead.
  #
  # cidrhost is evaluated ONLY on the derive branch. An explicit if/else (not
  # coalesce, which evaluates every argument eagerly) short-circuits it, so a
  # 6-7-digit positional VMID — which overflows the /24 host space — is safe with
  # EITHER dhcp = true OR a pinned static ipv4_address. This is what lets a
  # static-IP exception host (a DNS server, reachable before DNS is up) carry a
  # positional VMID instead of a legacy 3-digit one.
  container_ipv4 = {
    for k, v in var.containers : k => (
      try(v.dhcp, false) ? "dhcp" : (
        try(v.ip_config.ipv4_address, null) != null
        ? nonsensitive(v.ip_config.ipv4_address)
        : nonsensitive("${cidrhost(var.network_cidrs[v.vlan], v.vm_id)}/${split("/", var.network_cidrs[v.vlan])[1]}")
      )
    )
  }
  container_gateway = {
    for k, v in var.containers : k => (
      try(v.dhcp, false) ? null : nonsensitive(cidrhost(var.network_cidrs[v.vlan], 1))
    )
  }

  # Deterministic, locally-administered MAC per DHCP-first guest. The `02:` prefix
  # marks it locally-administered + unicast (RFC 7042). The remaining 5 octets are
  # a stable digest of the hostname, so the MAC is reproducible across rebuilds and
  # plan runs WITHOUT reading provider state. This is the join key downstream:
  # tofu-unifi pins this MAC to container_reserved_ip (DHCP reservation) and the
  # technitium_dns role points the A record at the same address. We set it on the
  # NIC explicitly because bpg/proxmox auto-generates a random MAC otherwise and
  # (v0.90+) does not expose it as an output — leaving nothing stable to reserve.
  container_mac = {
    for k, v in var.containers : k => format("02:%s:%s:%s:%s:%s",
      substr(md5(v.hostname), 0, 2), substr(md5(v.hostname), 2, 2),
      substr(md5(v.hostname), 4, 2), substr(md5(v.hostname), 6, 2),
    substr(md5(v.hostname), 8, 2))
  }

  # Reserved IP for DHCP-first guests that declare a reserved_host octet. This is
  # the address tofu-unifi pins the MAC to and the DNS A record resolves to. It is
  # decoupled from the (possibly 6-digit) positional vm_id: reserved_host is a real
  # host octet within the guest's VLAN /24, so cidrhost stays in range. Static
  # guests and DHCP guests with no reserved_host resolve to null (they advertise an
  # IP or FQDN via container_address instead). nonsensitive(): a single host address
  # is not independently secret and must flow into the non-sensitive inventory.
  container_reserved_ip = {
    for k, v in var.containers : k => (
      try(v.dhcp, false) && try(v.reserved_host, null) != null
      ? nonsensitive(cidrhost(var.network_cidrs[v.vlan], v.reserved_host)) : null
    )
  }

  # Reachable address each container advertises to downstream consumers (the
  # ansible_inventory ip field and the Traefik ingress backend). Static guests
  # advertise their derived host IP (CIDR mask stripped); DNS-first guests
  # (dhcp = true) advertise their FQDN {hostname}.{domain} so nothing downstream
  # pins an address the DHCP lease can change — reachable by name regardless of IP.
  container_address = {
    for k, v in var.containers : k => (
      try(v.dhcp, false)
      ? (var.domain != "" ? "${v.hostname}.${var.domain}" : v.hostname)
      : split("/", local.container_ipv4[k])[0]
    )
  }
  # VM IPv4/gateway + DHCP-first MAC/reserved-IP/advertised-address locals are
  # extracted into locals-vm-network.tf (locals merge across files in a module)
  # to keep this file under the shared _file-size workflow's 12 KB limit.

  # VGA type validation helper
  valid_vga_types = ["std", "cirrus", "vmware", "qxl"]

  # Resolver list for guest DNS: every resolver instance (one per Proxmox host)
  # for real cross-host HA. Every guest receives the WHOLE list and its stub
  # resolver fails over between entries natively — which is exactly why
  # resolvers take unique addresses and never share one.
  #
  # Selected by the `dns` tag, NOT by a name prefix. The prefix form
  # (`^technitium-dns`) silently excluded any instance named under the current
  # law, where the host digit and instance counter follow the app name. A
  # correctly-named new resolver would therefore have been given its own
  # address and then reached by nobody, with no error raised anywhere — and the
  # observable workaround for that invisibility is to pin the new instance to a
  # retired one's address, which is how two containers came to be statically
  # configured on a single IP.
  #
  # A tag survives renames; a name prefix encodes the naming law into a regex
  # and breaks the moment that law moves. Selection is unchanged today
  # (asserted in tests/dns_resolver_selection.tftest.hcl); the coupling is gone.
  #
  # Derived via container_ipv4 (honors static pins; no literal IPs in-repo) and
  # self-extending. Pi-hole is excluded — never brought up, VMID-derived IP was
  # the 2026-07-19 outage.
  dns_servers = [
    for name in sort(keys(var.containers)) :
    split("/", local.container_ipv4[name])[0]
    if contains(coalesce(try(var.containers[name].tags, null), []), "dns")
  ]

  # Internal networks for guest-firewall source scoping — derived from the
  # private RustFS per-VLAN CIDR map (the existing single source of truth),
  # so the real ranges never appear in committed files. nonsensitive(): the
  # list must flow into firewall rule attributes; the full map stays sensitive.
  internal_networks = nonsensitive(distinct(values(var.network_cidrs)))

  # Management network for the host firewall module: the compute VLAN CIDR
  # (Proxmox hosts live on compute). Inter-VLAN policy is enforced at UniFi;
  # the Proxmox host firewall keeps host-local protection only.
  management_network = nonsensitive(var.network_cidrs["compute"])

  # Splunk cluster IPs (host-form, no mask) for the firewall splunk-cluster
  # rules: the Splunk VM on siem + any containers tagged "splunk" (e.g.
  # splunk-mgmt), each at its own VLAN address.
  splunk_network_ips = nonsensitive(concat(
    [cidrhost(var.network_cidrs["siem"], var.splunk_vm_id)],
    [for k, v in var.containers : cidrhost(var.network_cidrs[v.vlan], v.vm_id) if contains(coalesce(v.tags, []), "splunk")]
  ))

  # Pipeline containers: HAProxy (haproxy tag) and Cribl Edge (cribl + edge tags)
  # These receive syslog and NetFlow data from network devices
  pipeline_container_ids = {
    for k, v in var.containers : k => v.vm_id
    if contains(coalesce(try(v.tags, null), []), "haproxy") || (
      contains(coalesce(try(v.tags, null), []), "cribl") && contains(coalesce(try(v.tags, null), []), "edge")
    )
  }

  # Notification containers: Mailpit and ntfy (notifications tag)
  notification_container_ids = {
    for k, v in var.containers : k => v.vm_id
    if contains(coalesce(try(v.tags, null), []), "notifications")
  }

  # Honeypot tag-filter locals (honeypot_container_ids,
  # honeypot_notify_container_ids) live in locals-honeypot.tf to keep this file
  # under the 12 KB size gate; locals merge across files in the module.

  # Vector database containers: Qdrant (vectordb tag)
  vectordb_container_ids = {
    for k, v in var.containers : k => v.vm_id
    if contains(coalesce(try(v.tags, null), []), "vectordb")
  }

  # RAG engine containers: LlamaIndex (rag tag)
  rag_container_ids = {
    for k, v in var.containers : k => v.vm_id
    if contains(coalesce(try(v.tags, null), []), "rag")
  }

  # APT caching proxy containers: apt-cacher-ng (apt-cache tag)
  apt_cacher_ng_container_ids = {
    for k, v in var.containers : k => v.vm_id
    if contains(coalesce(try(v.tags, null), []), "apt-cache")
  }

  # Object storage containers (object-storage tag) — RustFS.
  s3_container_ids = {
    for k, v in var.containers : k => v.vm_id
    if contains(coalesce(try(v.tags, null), []), "object-storage")
  }

  # OpenBao secrets-management containers (openbao tag)
  openbao_container_ids = {
    for k, v in var.containers : k => v.vm_id
    if contains(coalesce(try(v.tags, null), []), "openbao")
  }

  # Ingress containers (ingress tag) — the Traefik HA instances. Guest-firewalled
  # only when the define-disabled ingress firewall is enabled (see
  # modules/firewall/ingress_rules.tf); today these run un-firewalled, so keepalived
  # VRRP already flows freely between them. The rules exist pre-allowed so a future
  # enforcement flip never breaks the VIP.
  ingress_container_ids = {
    for k, v in var.containers : k => v.vm_id
    if contains(coalesce(try(v.tags, null), []), "ingress")
  }

  # HAProxy LXCs (haproxy tag) — receive delivered ACME certs for HTTPS frontends.
  # Distinct from pipeline_container_ids (which also includes Cribl Edge); this
  # local is dedicated to cert-delivery targeting.
  haproxy_container_ids = {
    for k, v in var.containers : k => v.vm_id
    if contains(coalesce(try(v.tags, null), []), "haproxy")
  }

  # Cribl Stream containers: tagged cribl + stream (receives from Edge, routes to Splunk)
  # Distinct from pipeline_container_ids (HAProxy + Cribl Edge) as it doesn't receive external traffic
  cribl_stream_container_ids = {
    for k, v in var.containers : k => v.vm_id
    if contains(coalesce(try(v.tags, null), []), "cribl") && contains(coalesce(try(v.tags, null), []), "stream")
  }

  # Cribl Edge containers: tagged cribl + edge. Subset of pipeline_container_ids
  # used by modules/firewall to grant license-telemetry HTTPS egress to Edge
  # without opening it for HAProxy in the same group.
  cribl_edge_container_ids = {
    for k, v in var.containers : k => v.vm_id
    if contains(coalesce(try(v.tags, null), []), "cribl") && contains(coalesce(try(v.tags, null), []), "edge")
  }

  # iDRAC KVM LXC: tagged "idrac" (domistyle/idrac6-based viewers, Docker-in-LXC)
  idrac_kvm_container_ids = {
    for k, v in var.containers : k => v.vm_id
    if contains(coalesce(try(v.tags, null), []), "idrac")
  }

  # Network-quality monitoring LXC (smokeping tag "monitoring"): SmokePing web UI
  # (80) + speedtest-exporter metrics (9798). Egress is open (output ACCEPT) so
  # fping/DNS/HTTPS probes can reach internal and external targets freely.
  monitoring_container_ids = {
    for k, v in var.containers : k => v.vm_id
    if contains(coalesce(try(v.tags, null), []), "monitoring")
  }

  # Hermes Agent LXC: tagged "hermes-agent". Autonomous agent that runs arbitrary
  # terminal + web tools; gets internal access + outbound-internal (reach the model
  # endpoint, DNS, NTP, Splunk logging) + outbound HTTPS for its web tools. The LXC
  # is the blast-radius boundary. (Hardening follow-up: route egress through a Squid
  # forward-proxy and replace outbound-internal with a microsegmented allowlist.)
  hermes_agent_container_ids = {
    for k, v in var.containers : k => v.vm_id
    if contains(coalesce(try(v.tags, null), []), "hermes-agent")
  }

  # postgres_container_ids + hindsight_container_ids live in
  # locals-memory.tf to keep this file under the 12 KB size gate.

  # Nautobot LXC (nautobot tag) — native IPAM/DCIM source of truth, web UI on
  # nautobot_web (8080). modules/firewall opens 8080 to it from internal.
  nautobot_container_ids = {
    for k, v in var.containers : k => v.vm_id
    if contains(coalesce(try(v.tags, null), []), "nautobot")
  }
}
