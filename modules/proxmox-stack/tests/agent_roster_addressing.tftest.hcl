# Tests for roster firewall system-address validation and derivation.
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
  network_cidrs           = { for name, id in var.vlan_ids : name => "203.0.113.0/24" }
  domain                  = "example.test"
  nodes                   = { node-example = { role = "node-1" } }
}

run "logical_owner_accepts_local_router_key_class" {
  command = plan

  variables {
    agents = {
      "example-owner" = {
        display            = "Example Owner"
        purpose            = "Exercise the local router key class"
        router_key_class   = "local"
        trust_tier         = "untrusted"
        native_binding_ref = "tests/runtime/example-owner"
      }
    }
  }

  assert {
    condition     = output.ansible_inventory.agents["example-owner"].router_key_class == "local"
    error_message = "A logical owner must retain the local router key class."
  }
}

run "agent_router_key_class_must_be_known" {
  command = plan

  variables {
    agents = {
      "example-owner" = {
        display            = "Example Owner"
        purpose            = "Exercise the router key class guard"
        router_key_class   = "unknown"
        trust_tier         = "untrusted"
        native_binding_ref = "tests/runtime/example-owner"
      }
    }
  }

  expect_failures = [var.agents]
}

run "agent_owned_cribl_requires_a_host" {
  command = plan

  variables {
    containers = {
      "agent-example-1" = { vm_id = 240, node_name = "node-example", vlan = "apps" }
    }
    agents = {
      "agent-example-1" = {
        name = "research-scout", display = "Scout", purpose = "Search example records", owns = ["cribl"]
      }
    }
  }

  expect_failures = [output.agents]
}

run "agent_owned_cribl_rejects_a_dhcp_stream_host" {
  command = plan

  variables {
    containers = {
      "agent-example-1" = { vm_id = 240, node_name = "node-example", vlan = "apps" }
      "cribl-dhcp-example" = {
        vm_id = 241, node_name = "node-example", vlan = "apps", dhcp = true, tags = ["cribl", "stream"]
      }
    }
    agents = {
      "agent-example-1" = {
        name = "research-scout", display = "Scout", purpose = "Search example records", owns = ["cribl"]
      }
    }
  }

  expect_failures = [output.agents]
}

run "agent_system_hosts_use_pinned_addresses" {
  command = plan

  variables {
    containers = {
      "agent-example-1" = { vm_id = 240, node_name = "node-example", vlan = "apps" }
      "splunk-pinned-example" = {
        vm_id     = 242, node_name = "node-example", vlan = "siem", tags = ["splunk"]
        ip_config = { ipv4_address = "203.0.113.42/24" }
      }
      "cribl-pinned-example" = {
        vm_id     = 1234567, node_name = "node-example", vlan = "apps", tags = ["cribl", "stream"]
        ip_config = { ipv4_address = "203.0.113.43/24" }
      }
    }
    agents = {
      "agent-example-1" = {
        name = "research-scout", display = "Scout", purpose = "Search example records", owns = ["splunk", "cribl"]
      }
    }
  }

  assert {
    condition     = local.agent_system_hosts["splunk"] == ["203.0.113.99", "203.0.113.42"]
    error_message = "Splunk firewall hosts must include the pinned address: ${jsonencode(local.agent_system_hosts["splunk"])}."
  }

  assert {
    condition = (
      local.agent_system_hosts["cribl"] == ["203.0.113.43"] &&
      local.container_ipv4["cribl-pinned-example"] == "203.0.113.43/24"
    )
    error_message = "Cribl firewall hosts must use the pinned address with its prefix stripped."
  }
}
