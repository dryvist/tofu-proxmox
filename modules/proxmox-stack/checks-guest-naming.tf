# Guest naming law, enforced at plan time.
#
# THE LAW. A guest name is `<app>-<NM>`: `N` is the node's LOGICAL DIGIT, `M` a
# zero-based counter for that app on that node. Always two digits, never one.
# `<app>` is the bare application name — `technitium`, not `technitium-dns`; the
# protocol is redundant when the app IS the protocol. See
# docs/GUEST_NAMING.md for the convention in full.
#
# THE CONDITION, which is the part that gets forgotten. A name encoding a node
# is only ever true for a guest that STAYS on that node. Two guests in this
# estate encode a node they were evacuated away from, and their names have been
# lying ever since. So the digit is for PINNED guests — the ones whose
# application supplies its own cross-node redundancy (quorum members, resolver
# pairs, load-balanced ingress). A guest that relocates for its availability
# (`ha = true`) must carry no node digit at all: the moment HA moves it, a
# digit in its name is false.
#
# SINGLE SOURCE OF TRUTH. The logical digit is `nodes.<node>.logical_id` in the
# deployment object (variables-infrastructure.tf) and is declared exactly once.
# It is deliberately NOT the corosync node id: corosync numbers nodes by join
# order, which is an accident of cluster history, while the logical digit is
# chosen to be stable and memorable. The two diverge today and that divergence
# is intentional — never "reconcile" one to the other.
#
# SCOPE. A guest is judged only when its node declares a `logical_id`, matching
# the convention checks-storage.tf already uses: a node with nothing declared
# has nothing to compare against, so judging it would invent a verdict.
locals {
  # node key -> logical digit, for nodes that declare one. The single map.
  node_logical_ids = {
    for name, n in var.nodes : name => n.logical_id
    if try(n.logical_id, null) != null
  }

  # Two nodes sharing a digit makes every name built from it ambiguous. This is
  # exactly why one node in this estate takes a digit its hardware model does
  # not suggest — the obvious digit was already taken.
  duplicate_logical_ids = [
    for id in distinct(values(local.node_logical_ids)) :
    "logical_id ${id} is claimed by more than one node (${join(", ", sort([for k, v in local.node_logical_ids : k if v == id]))})"
    if length([for v in values(local.node_logical_ids) : v if v == id]) > 1
  ]

  # Every guest, containers and VMs alike, as {name, node, relocatable}. VMs
  # carry no `ha` attribute today; try() keeps this one list rather than two.
  guest_naming_subjects = concat(
    [for k, v in var.containers : {
      name = v.hostname
      node = v.node_name
      kind = "container"
      # `ha = true` is the opt-in that lets Proxmox relocate a guest (ha.tf).
      # It is the only machine-readable statement in the estate that a guest
      # moves for its availability, so it is what "relocatable" means here.
      relocatable = try(v.ha, false)
    }],
    [for k, v in var.vms : {
      name        = v.name
      node        = v.node_name
      kind        = "vm"
      relocatable = try(v.ha, false)
    }]
  )

  guest_naming_violations = concat(local.duplicate_logical_ids, flatten([
    for g in local.guest_naming_subjects : [
      for m in regexall("-([0-9]+)$", g.name) : (
        length(m[0]) != 2
        ? "${g.kind} \"${g.name}\": numeric suffix \"-${m[0]}\" must be exactly two digits — <node-digit><instance>, e.g. -${local.node_logical_ids[g.node]}0"
        : g.relocatable
        ? "${g.kind} \"${g.name}\": relocatable guest (ha = true) must not encode a node — HA moves it and the digit becomes a lie. Drop the numeric suffix."
        : substr(m[0], 0, 1) != tostring(local.node_logical_ids[g.node])
        ? "${g.kind} \"${g.name}\": node digit ${substr(m[0], 0, 1)} does not match node \"${g.node}\" (logical_id ${local.node_logical_ids[g.node]}). Expected a name ending -${local.node_logical_ids[g.node]}<instance>."
        : ""
      ) if !contains(keys(var.guest_naming_exceptions), g.name)
    ]
    if contains(keys(local.node_logical_ids), g.node)
  ]))

  guest_naming_failures = [for v in local.guest_naming_violations : v if v != ""]
}

# Guests whose names predate the law and are not renamed by this change. A
# rename is a separate, riskier operation — a guest deriving its cluster
# identity from its hostname rejoins as a NEW peer, leaving the old entry as a
# failed voter — so the renames ride a planned resize instead.
#
# The roster is a real-guest-name list, so it is NOT committed here — a public
# repository is exactly the wrong place for it (same reason node_name-to-guest
# topology never appears in prose). It lives in the private desired state
# alongside the node digit map it is judged against (`deployment.json`'s
# `guest_naming_exceptions`, wired in main.tf), keyed by guest name with the
# reason as the value so an entry cannot be added silently. Only the rule is
# public; the roster stays private. Shrink it; never grow it.
variable "guest_naming_exceptions" {
  description = "Guest names exempted from the node-digit naming law, name -> reason. Sourced from the private desired state, never committed here — every entry is pre-law debt awaiting a planned rename."
  type        = map(string)
  default     = {}
}

# terraform_data is a provider-less plan-time anchor, the same idiom checks.tf
# and checks-storage.tf use: the precondition is the assertion, and it fails the
# plan rather than warning like a `check` block would.
resource "terraform_data" "guest_naming_guard" {
  input = length(local.guest_naming_failures)

  lifecycle {
    precondition {
      condition     = length(local.guest_naming_failures) == 0
      error_message = "Guest naming law violated (docs/GUEST_NAMING.md):\n  - ${join("\n  - ", local.guest_naming_failures)}"
    }
  }
}
