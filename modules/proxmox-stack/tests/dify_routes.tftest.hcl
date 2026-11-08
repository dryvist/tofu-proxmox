# Tests for the Dify route set: Dify Community has no SSO, so its one route
# skips the Authelia forwardAuth and Dify's own login protects every path.
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
    vm_id      = 200
    name       = "splunk-example"
    ip_address = "192.0.2.200"
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
  vm_ssh_public_key       = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHVTuJXKeZvvLsHLW0Fb4IPre13X8iheexMI8n3vT46+ fixture@example.test"
  proxmox_user            = "root"
  proxmox_ssh_private_key = "-----BEGIN FIXTURE PLACEHOLDER-----\nfixture-value-redacted\n-----END FIXTURE PLACEHOLDER-----"
  network_cidrs           = { for name, id in var.vlan_ids : name => "192.168.${id}.0/24" }
  domain                  = "example.test"
  nodes                   = { node-example = { role = "node-1" } }
}

run "dify_is_one_route_without_the_authelia_gate" {
  command = plan

  variables {
    containers = {
      dify = { vm_id = 241, node_name = "node-example", vlan = "apps" }
    }
    agents = {}
  }

  assert {
    condition     = one([for r in output.ansible_inventory.ingress : r if r.name == "dify"]).sso == false && one([for r in output.ansible_inventory.ingress : r if r.name == "dify"]).path_prefix == null
    error_message = "The dify route must skip the Authelia gate and carry no path prefix."
  }

  assert {
    condition     = length([for r in output.ansible_inventory.ingress : r if r.name != "dify" && try(r.hostname, null) == "dify"]) == 0
    error_message = "Dify needs no separate machine-path rows once its whole host skips the gate."
  }
}
