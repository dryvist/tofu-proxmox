# Tests for the ingress source class on routes of roster-owned systems.
# All runs use mocked providers and plan only.

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
    name        = "splunk-example"
    ip_address  = "192.0.2.200"
    mac_address = "BC:24:11:00:00:C8"
    tiered_disks = {
      fast = { datastore_id = "fast-example", interface = "virtio2", size = 1024, backup = true }
      bulk = { datastore_id = "bulk-example", interface = "virtio3", size = 2048, backup = false }
    }
  }
}

override_module {
  target = module.firewall
  outputs = {
    cluster_firewall_enabled            = true
    vm_firewall_enabled                 = true
    container_firewall_enabled          = true
    pipeline_container_firewall_enabled = true
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
  vm_ssh_public_key       = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestKeyData test@example.test"
  proxmox_user            = "root"
  proxmox_ssh_private_key = "-----BEGIN OPENSSH PRIVATE KEY-----\ntest\n-----END OPENSSH PRIVATE KEY-----"
  network_cidrs           = { for name, id in var.vlan_ids : name => "192.168.${id}.0/24" }
  domain                  = "example.test"
  nodes                   = { node-example = { role = "node-1" } }
}

run "empty_agent_roster_leaves_ingress_without_source_class" {
  command = plan

  variables {
    agents = {}
  }

  assert {
    condition = length([
      for route in output.ansible_inventory.ingress : route
      if try(route.source_class, null) != null
    ]) == 0
    error_message = "An empty agent roster must leave every published ingress route without a source_class field."
  }
}

run "splunk_owner_sets_source_class_only_on_owned_routes" {
  command = plan

  variables {
    containers = {
      "agent-example-1" = { vm_id = 240, node_name = "node-example", vlan = "apps" }
    }
    agents = {
      "agent-example-1" = {
        name = "research-scout", display = "Scout", purpose = "Search records", owns = ["splunk"]
      }
    }
  }

  assert {
    condition = toset([
      for route in output.ansible_inventory.ingress : route.name
      if try(route.source_class, "") != ""
      ]) == toset(["splunk", "splunk-mgmt"]) && alltrue([
      for route in output.ansible_inventory.ingress :
      try(route.source_class, "") == "agent-owner"
      if contains(["splunk", "splunk-mgmt"], route.name)
    ])
    error_message = "Only splunk and splunk-mgmt must carry agent-owner when the roster owns splunk."
  }
}
