mock_provider "proxmox" {}
mock_provider "tls" {}
mock_provider "random" {}
mock_provider "aws" {}
mock_provider "null" {}

override_module {
  target = module.splunk_vm
  outputs = {
    vm_id      = 200
    name       = "splunk-aio"
    ip_address = "192.0.2.200"
    tiered_disks = {
      fast = { datastore_id = "fast-splunk", interface = "virtio2", size = 1024, backup = true }
      bulk = { datastore_id = "bulk-splunk", interface = "virtio3", size = 2048, backup = false }
    }
  }
}

variables {
  vm_ssh_public_key       = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestKeyData test@test"
  proxmox_user            = "root"
  proxmox_ssh_private_key = "-----BEGIN OPENSSH PRIVATE KEY-----\ntest\n-----END OPENSSH PRIVATE KEY-----"
  network_cidrs           = { for name, id in var.vlan_ids : name => "192.168.${id}.0/24" }
  nodes = {
    a = { role = "compute", cpu_vendor = "amd" }
    b = { role = "compute", cpu_vendor = "amd" }
    c = { role = "compute", cpu_vendor = "intel" }
  }
  containers = { app = { vm_id = 101, node_name = "a", vlan = "data", cpu_vendor = "amd" } }
  vms        = { app = { vm_id = 102, node_name = "c", vlan = "data", cpu_vendor = "intel" } }
}

run "matching_vendors" {
  command = plan
  assert {
    condition     = length(local.cpu_placement_mismatches) == 0
    error_message = "Matching guest and node vendors must pass."
  }
}

run "container_mismatch" {
  command = plan
  variables { containers = { app = { vm_id = 101, node_name = "c", vlan = "data", cpu_vendor = "amd" } } }
  expect_failures = [terraform_data.cpu_placement_guard]
}

run "vm_mismatch" {
  command = plan
  variables { vms = { app = { vm_id = 102, node_name = "a", vlan = "data", cpu_vendor = "intel" } } }
  expect_failures = [terraform_data.cpu_placement_guard]
}

run "missing_vendors_allowed" {
  command = plan
  variables {
    nodes      = { a = { role = "compute" } }
    containers = { app = { vm_id = 101, node_name = "a", vlan = "data", cpu_vendor = "amd" } }
    vms        = { app = { vm_id = 102, node_name = "a", vlan = "data" } }
  }
  assert {
    condition     = length(local.cpu_placement_mismatches) == 0
    error_message = "Undeclared vendors must remain compatible."
  }
}
