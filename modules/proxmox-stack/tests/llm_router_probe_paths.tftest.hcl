# Tests for the published LLM router health-check paths and ingress routes.
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

run "router_probe_paths_are_published_and_used_by_ingress" {
  command = plan

  variables {
    containers = {
      "fabric-router-fixture" = {
        vm_id            = 501000
        node_name        = "node-example"
        dhcp             = true
        hostname         = "fabric-router-fixture"
        vlan             = "ai"
        memory_dedicated = 4096
        tags             = ["terraform", "container", "llm-router"]
      }
    }
  }

  assert {
    condition = output.ansible_inventory.constants.llm_router_probe_paths == {
      liveliness = "/health/liveliness"
      readiness  = "/health/readiness"
    }
    error_message = "ansible_inventory.constants.llm_router_probe_paths must publish both router probe paths."
  }

  assert {
    condition = (
      toset([
        for route in output.ansible_inventory.ingress : route.name
        if contains(["llm", "llm-ui", "llm-ui-legacy"], route.name)
        ]) == toset(["llm", "llm-ui", "llm-ui-legacy"]) && alltrue([
        for route in output.ansible_inventory.ingress :
        route.health_check_path == output.ansible_inventory.constants.llm_router_probe_paths.readiness
        if contains(["llm", "llm-ui", "llm-ui-legacy"], route.name)
      ])
    )
    error_message = "Each LLM router ingress row must use the published readiness path."
  }
}
