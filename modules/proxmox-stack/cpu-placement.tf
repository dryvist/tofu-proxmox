# CPU-vendor placement guard (plan time).
#
# A live migration between CPU vendors can hang the guest even with a generic
# CPU model, and the provider live-migrates a running HA guest on any
# node_name change. Preconditions cannot see the prior node, so the guard pins
# each guest that declares cpu_vendor to nodes of that vendor: a cross-vendor
# move can then never be planned. HA failover (a cold restart from a replica)
# may still land on another vendor, so no strict vendor HA rule is emitted.
locals {
  cpu_placement_guests = merge(
    { for k, v in var.containers : "ct:${k}" => { node = v.node_name, vendor = v.cpu_vendor } },
    { for k, v in var.vms : "vm:${k}" => { node = v.node_name, vendor = v.cpu_vendor } },
  )
  cpu_placement_mismatches = [
    for name, guest in local.cpu_placement_guests :
    "${name} (${guest.vendor}) on ${guest.node} (${var.nodes[guest.node].cpu_vendor})"
    if guest.vendor != null && try(var.nodes[guest.node].cpu_vendor, null) != null && guest.vendor != try(var.nodes[guest.node].cpu_vendor, null)
  ]
  cpu_vendors = concat(
    [for node in values(var.nodes) : node.cpu_vendor],
    [for guest in values(local.cpu_placement_guests) : guest.vendor],
  )
}

resource "terraform_data" "cpu_placement_guard" {
  input = local.cpu_placement_guests

  lifecycle {
    precondition {
      condition     = alltrue([for vendor in local.cpu_vendors : vendor == null ? true : contains(["amd", "intel"], vendor)])
      error_message = "cpu_vendor must be amd or intel when declared."
    }
    precondition {
      condition     = length(local.cpu_placement_mismatches) == 0
      error_message = "Guest cpu_vendor differs from its node's cpu_vendor: ${join(", ", local.cpu_placement_mismatches)}. Move it cold (stop, migrate, start) and change cpu_vendor in the same edit."
    }
  }
}
