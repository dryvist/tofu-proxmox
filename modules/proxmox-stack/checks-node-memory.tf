# Budget the complete planned allocation, including generated containers.
# Live usage and ballooning do not reduce the RAM a guest may consume.
locals {
  guest_memory_allocations = concat(
    [for guest in values(var.containers) : {
      node = guest.node_name
      mb   = guest.memory_dedicated
    }],
    [for guest in values(var.vms) : {
      node = guest.node_name
      mb   = guest.memory_dedicated
    }],
    [{ node = var.splunk_node_name, mb = var.splunk_memory }],
  )

  node_memory_allocated_mb = {
    for node in keys(var.nodes) : node => sum(concat([0], [
      for guest in local.guest_memory_allocations : guest.mb if guest.node == node
    ]))
  }

  overcommitted_memory_nodes = {
    for node, cfg in var.nodes : node => {
      allocated_mb = local.node_memory_allocated_mb[node]
      budget_mb    = cfg.memory_budget_mb
    }
    if cfg.memory_budget_mb != null && local.node_memory_allocated_mb[node] > coalesce(cfg.memory_budget_mb, 0)
  }
}

resource "terraform_data" "node_memory_capacity_guard" {
  input = local.node_memory_allocated_mb

  lifecycle {
    precondition {
      condition = length(local.overcommitted_memory_nodes) == 0
      error_message = format("Planned guest RAM exceeds the node memory budget: %s. Reduce allocations or change placement; the budget must reserve RAM for the host.", join("; ", [
        for node, memory in local.overcommitted_memory_nodes :
        format("%s allocates %d MiB against %d MiB", node, memory.allocated_mb, memory.budget_mb)
      ]))
    }
  }
}
