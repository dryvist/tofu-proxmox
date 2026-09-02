# Container schema notes

Long-form rationale for fields of the `containers` variable in
`modules/proxmox-stack/variables-containers.tf`. It lives here rather than
inline so that file stays under the repository's per-file size gate; each
field there carries a one-line summary and a pointer to its section below.

## `dhcp` — DNS-first addressing

DNS-first addressing (see docs vmid-network-tiers). When true the guest
takes its address by DHCP and is referenced by FQDN everywhere — no
vm_id-derived IP is computed, so it may carry a 6-digit positional VMID
the /24 cidrhost math could not express. DNS owns the address, so the
guest stays reachable across re-IP and rebuild.

This is the DEFAULT for ordinary guests, and it is a plain pool lease: there
is no reserved octet to declare, because there is nothing to declare it
against. The gateway answers DNS for its own lease-table clients, so a
leased guest is reachable by name with its address written down nowhere.
(A `reserved_host` field once pinned a hand-chosen octet here, in the
controller, and in the DNS zone at once — one address in three systems,
which drifted repeatedly. Removed; do not reintroduce it.)

Set dhcp = false ONLY for network and critical guests (resolvers, ingress,
secrets) — they pin ip_config.ipv4_address so that relocating one of them
never requires touching the guests that point at it.

## `mount_points` — additional volumes

Mount points (additional volumes mounted into the container)
Omit `size` for host-directory bind-mounts (volume = host path such as
"/example-pool/media"); set it to allocate a new managed volume.
`backup` defaults to TRUE here, inverting the provider's default. A volume
mount point is where a container's data lives, so false silently produces
a rootfs-only backup and a vzdump job that reports success having captured
none of it. Set false only for contents that are reproducible or backed up
by their own writer, and say which in a comment there.

NOTE: `mount_point` is in this module's ignore_changes (see
modules/proxmox-container/main.tf), so mounts are effectively set-once.
This default governs newly created containers; an existing one needs the
flag set out of band, landing in its pending config until it next stops.

## `ha_replication_target` — the only relocation target

The node holding this guest's storage-replication (pvesr) copy, and so the
ONLY node a cluster HA manager may relocate it to on node loss. Unset
means the guest has no replica and must be restarted in place.

Declared per guest rather than as a global node pair: a pair is a property
of a guest's storage, not of the cluster, and the single global pair this
replaces could not express a guest whose replica lived anywhere else — so
such guests were simply left out of HA, which is how a singleton with no
relocation target went unrecovered through a node failure.

Consumers must treat a missing value as "not replicated", never as a
default node: relocating a guest onto a node with no copy of its data
fails the start and latches the service in an error state.

## `startup_order` — boot ordering

Unset, boot order is derived from the VMID in
`modules/proxmox-container/main.tf`: a guest below 1000 uses its VMID
directly, everything else uses the VMID's thousands prefix. That encodes tier
only by accident of the numbering scheme, so a legacy three-digit guest sorts
ahead of every six-digit one and boots before the ingress, the secret store
and the log collectors. Set `startup_order` on any guest whose boot position
is load-bearing; lower starts first. Leaving it unset keeps the derivation, so
adding the field changes no existing guest.
