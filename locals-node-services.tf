# Per-node ("DaemonSet-style") service expansion, split out of main.tf so that
# file stays under the shared _file-size workflow's 12 KB error threshold — the
# same treatment modules/proxmox-stack gives its own locals (locals-ingress-ha,
# locals-vm-network, and friends). Locals merge across files, so this is a pure
# relocation with no behaviour change.
locals {
  # Per-node ("DaemonSet-style") service expansion: one container per eligible
  # node, generated from a single template instead of a hand-copied block per
  # node (the pattern the `_ingress_ha_comment` in deployment.json.example
  # used to document — "add another by copying the block and bumping
  # vm_id/node_name"). `node_services` in the deployment object is a map of
  # service name -> template; `deployment.json.example` documents the shape.
  # Traefik is the first consumer. A future per-node service (e.g. a
  # technitium secondary) is a new `node_services` entry, no code change here.
  #
  # Eligibility is `commissioned && services_enabled` on each node — distinct
  # gates: `commissioned` means "hardware installed at all", `services_enabled`
  # means "eligible for per-node service placement right now" (e.g. a
  # commissioned node mid storage-rebuild keeps commissioned=true but sets
  # services_enabled=false until the rebuild completes, and the DaemonSet
  # expansion skips it without touching anything else the node already runs).
  # A node with no entry in the template's `per_node` map is skipped even if
  # otherwise eligible — vm_id/IP are reserved-octet allocations, never
  # derived by formula, so an unlisted node has no safe address to assign.
  node_service_templates = try(local.deployment.node_services, {})
  # Naming law: every generated name ends in a two-digit <node-id><counter>
  # suffix (pve3 instance 0 -> "-30"), never a single digit -- names are
  # deliberately non-transferable (rebuild-from-scratch doctrine), same as
  # the openbao_generated_containers suffix above. `suffix` is numeric in
  # per_node and zero-padded here (%02d), matching that pattern exactly.
  # Whether each generated instance is DNS-first (DHCP) or takes a static
  # address, resolved ONCE per service/node. The addressing block below reads
  # this three times — for `dhcp`, for `reserved_host`, and for `ip_config` —
  # and those three must agree by construction: a guest that says dhcp = true
  # while carrying an ip_config, or dhcp = true with no reserved_host, is a
  # guest whose declared address and actual address can disagree.
  node_service_use_dhcp = {
    for service_name, tmpl in local.node_service_templates :
    service_name => {
      for node_name, entry in try(tmpl.per_node, {}) :
      node_name => try(tmpl.dhcp, false) || !contains(keys(entry), "host_octet")
    }
  }

  node_service_containers = merge([
    for service_name, tmpl in local.node_service_templates : {
      for node_name, node in local.deployment.nodes :
      format("%s%02d", try(tmpl.name_prefix, "${service_name}-"), tmpl.per_node[node_name].suffix) => merge(
        try(tmpl.container_defaults, {}),
        {
          vm_id     = tmpl.per_node[node_name].vm_id
          vlan      = tmpl.vlan
          hostname  = format("%s%02d", try(tmpl.name_prefix, "${service_name}-"), tmpl.per_node[node_name].suffix)
          node_name = node_name
        },
        # Addressing: full DHCP is the standard (static assignment, when wanted,
        # is UniFi's job driven by the Nautobot SSOT — not a tofu-side octet).
        # A template that still carries per_node host_octet reservations (the
        # pre-DHCP traefik/VIP allocation) keeps its static ip_config unchanged.
        #
        # ONE object with null-valued branches, never a conditional BETWEEN two
        # object shapes. HCL type-checks both arms of a conditional regardless
        # of which one the condition selects, and objects only unify when their
        # attribute sets match — so `... ? { dhcp = ... } : { ip_config = ... }`
        # is a hard error on every evaluation:
        #
        #   Error: Inconsistent conditional result types
        #   'true' value includes object attribute "dhcp", which is absent in
        #   the 'false' value.
        #
        # That is a static failure, so it fired for any template at all and was
        # the second of the two reasons nothing could adopt this generator.
        # Emitting both attributes with a null on the inapplicable one keeps the
        # type constant; the container schema declares both optional, and an
        # explicit null falls back to the declared default.
        {
          dhcp = local.node_service_use_dhcp[service_name][node_name]
          # Required whenever dhcp = true — var.containers validates it, because
          # it is the octet UniFi pins the deterministic MAC to and the octet the
          # DNS A record resolves to. A template may pin one per node; absent
          # that it defaults to the name suffix, exactly as the openbao voters
          # derive theirs (`reserved_host = peer.suffix`), so the reservation and
          # the two-digit name cannot drift apart.
          reserved_host = (
            local.node_service_use_dhcp[service_name][node_name]
            ? try(tmpl.per_node[node_name].reserved_host, tmpl.per_node[node_name].suffix)
            : null
          )
          ip_config = (
            local.node_service_use_dhcp[service_name][node_name]
            ? null
            : {
              ipv4_address = format(
                "%s/%s",
                cidrhost(local.deployment.network_cidrs[tmpl.vlan], tmpl.per_node[node_name].host_octet),
                split("/", local.deployment.network_cidrs[tmpl.vlan])[1],
              )
            }
          )
        }
      )
      # `commissioned` is read through try() for the same reason
      # `services_enabled` is: this iterates the RAW deployment object, which
      # jsondecode gives no schema defaults. The typed `nodes` variable in
      # modules/proxmox-stack declares `commissioned = optional(bool, true)`,
      # so a node that omits the key IS commissioned everywhere else in the
      # stack — reading it bare here made this expansion the one place that
      # disagreed, and it disagreed by erroring the whole plan
      # ("This object does not have an attribute named commissioned") rather
      # than by skipping the node. That is why no service could adopt this
      # generator while any node omitted the key.
      if try(node.commissioned, true) && try(node.services_enabled, true) && contains(keys(try(tmpl.per_node, {})), node_name)
    }
  ]...)
}
