# Sanitized allocations exercise the same hard budget used by every plan.

mock_provider "proxmox" {
  mock_data "proxmox_virtual_environment_datastores" {
    defaults = {
      datastores = [
        { id = "local", type = "dir", content_types = ["iso", "vztmpl", "backup"] },
        { id = "local-zfs", type = "zfspool", content_types = ["images", "rootdir"] },
      ]
    }
  }
}
mock_provider "tls" {}
mock_provider "random" {}
mock_provider "aws" {}
mock_provider "null" {}

override_module {
  target = module.storage
  outputs = {
    cloud_init_file_id   = null
    datastores_available = {}
    storage_validated    = true
  }
}

override_module {
  target = module.splunk_vm
  outputs = {
    vm_id       = 200
    name        = "splunk-aio"
    ip_address  = "192.0.2.200"
    mac_address = "BC:24:11:00:00:C8"
    tiered_disks = {
      fast = { datastore_id = "fast-splunk", interface = "virtio2", size = 1024, backup = true }
      bulk = { datastore_id = "bulk-splunk", interface = "virtio3", size = 2048, backup = false }
    }
  }
}

override_module {
  target = module.acme_certificates
  outputs = {
    acme_accounts = {}
    dns_plugins   = {}
    certificates  = {}
  }
}

variables {
  vm_ssh_public_key       = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestKeyData test@test"
  proxmox_user            = "root"
  proxmox_ssh_private_key = "-----BEGIN OPENSSH PRIVATE KEY-----\ntest\n-----END OPENSSH PRIVATE KEY-----"
  network_cidrs           = { for name, id in var.vlan_ids : name => "192.168.${id}.0/24" }
  splunk_node_name        = "compute-a"
  splunk_memory           = 12288
  nodes = {
    compute-a = { role = "compute", memory_budget_mb = 29761 }
    server-a  = { role = "server", memory_budget_mb = 176506 }
  }
  # Sanitized measured shape: 128.5/184.5 GiB committed, 31.06/180.37 GiB
  # physical, with explicit host reserves deducted from the node budgets.
  containers = {
    worker-a          = { vm_id = 101, node_name = "compute-a", vlan = "data", memory_dedicated = 57344 }
    worker-b          = { vm_id = 102, node_name = "compute-a", vlan = "data", memory_dedicated = 57344 }
    generated-service = { vm_id = 103, node_name = "compute-a", vlan = "data", memory_dedicated = 4608 }
    database-a        = { vm_id = 104, node_name = "server-a", vlan = "data", memory_dedicated = 65536 }
    database-b        = { vm_id = 105, node_name = "server-a", vlan = "data", memory_dedicated = 65536 }
  }
  vms = { worker-vm = { vm_id = 106, node_name = "server-a", vlan = "data", memory_dedicated = 57856 } }
}
run "measured_overcommit_fails_closed" {
  command = plan
  plan_options { target = [terraform_data.node_memory_capacity_guard] }
  expect_failures = [terraform_data.node_memory_capacity_guard]
  assert {
    condition     = local.node_memory_allocated_mb == { compute-a = 131584, server-a = 188928 }
    error_message = "All container, VM and dedicated VM allocations must count."
  }
}
run "placements_with_host_reserve_fit" {
  command = plan
  plan_options { target = [terraform_data.node_memory_capacity_guard] }
  variables {
    containers = {
      worker     = { vm_id = 101, node_name = "compute-a", vlan = "data", memory_dedicated = 15872 }
      database-a = { vm_id = 104, node_name = "server-a", vlan = "data", memory_dedicated = 65536 }
      database-b = { vm_id = 105, node_name = "server-a", vlan = "data", memory_dedicated = 65536 }
    }
    vms = { worker-vm = { vm_id = 106, node_name = "server-a", vlan = "data", memory_dedicated = 43008 } }
  }
  assert {
    condition     = local.node_memory_allocated_mb == { compute-a = 28160, server-a = 174080 }
    error_message = "Accounting must retain every dedicated allocation."
  }
  assert {
    condition     = var.nodes["compute-a"].memory_budget_mb == 29761
    error_message = "The node type must retain the budget."
  }
}
run "legacy_nodes_without_budgets_remain_compatible" {
  command = plan
  plan_options { target = [terraform_data.node_memory_capacity_guard] }
  variables { nodes = { compute-a = { role = "compute" } } }
  assert {
    condition     = length(local.overcommitted_memory_nodes) == 0
    error_message = "An absent budget must not invent capacity."
  }
}
run "fractional_budget_rejected" {
  command = plan
  plan_options { target = [terraform_data.node_memory_capacity_guard] }
  variables { nodes = { compute-a = { role = "compute", memory_budget_mb = 1.5 } } }
  expect_failures = [var.nodes]
}
run "zero_budget_rejected" {
  command = plan
  plan_options { target = [terraform_data.node_memory_capacity_guard] }
  variables { nodes = { compute-a = { role = "compute", memory_budget_mb = 0 } } }
  expect_failures = [var.nodes]
}

run "exact_budget_is_accepted" {
  command = plan
  plan_options { target = [terraform_data.node_memory_capacity_guard] }
  variables {
    nodes = {
      compute-a = { role = "compute", memory_budget_mb = 131584 }
      server-a  = { role = "server", memory_budget_mb = 188928 }
    }
  }
}
run "negative_budget_rejected" {
  command = plan
  plan_options { target = [terraform_data.node_memory_capacity_guard] }
  variables { nodes = { compute-a = { role = "compute", memory_budget_mb = -1 } } }
  expect_failures = [var.nodes]
}
