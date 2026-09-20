# Tests for generated guest naming (locals.tf: guest_hostname_containers /
# guest_hostname_vms). There is no guard any more — the name cannot deviate
# because it is a pure function of the desired-state map key and the guest's
# own vm_id, never read from a hand-set hostname/name field. See
# docs/GUEST_NAMING.md.
#
# All runs use mock providers (no real infrastructure needed).

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
  proxmox_ssh_private_key = "-----BEGIN OPENSSH PRIVATE KEY-----\ntest\n-----END OPENSSH PRIVATE KEY-----"
  network_cidrs           = { for name, id in var.vlan_ids : name => "192.168.${id}.0/24" }

  nodes = {
    node-alpha = { role = "node-1" }
  }
}

run "container_key_with_no_suffix_generates_key_dash_vmid" {
  command = plan

  variables {
    containers = {
      foo = {
        node_name = "node-alpha"
        vm_id     = 301050
        hostname  = "ignored-input-value"
        vlan      = "apps"
        dhcp      = true
      }
    }
  }

  assert {
    condition     = local.guest_hostname_containers["foo"] == "foo-301050"
    error_message = "a key with no trailing numeric suffix must generate <key>-<vm_id>, got ${local.guest_hostname_containers["foo"]}"
  }
}

run "vm_key_with_trailing_digit_strips_it_from_the_app" {
  command = plan

  variables {
    vms = {
      "bar-2" = {
        node_name = "node-alpha"
        vm_id     = 301060
        name      = "ignored-input-value"
        vlan      = "apps"
        dhcp      = true
      }
    }
  }

  assert {
    condition     = local.guest_hostname_vms["bar-2"] == "bar-301060"
    error_message = "a key's trailing -<digits> must be stripped before appending vm_id, got ${local.guest_hostname_vms["bar-2"]}"
  }
}

run "hardware_token_style_key_still_strips_only_the_trailing_digits" {
  command = plan

  variables {
    containers = {
      "baz-540" = {
        node_name = "node-alpha"
        vm_id     = 301070
        vlan      = "apps"
        dhcp      = true
      }
    }
  }

  assert {
    condition     = local.guest_hostname_containers["baz-540"] == "baz-301070"
    error_message = "app is the key minus its trailing digit run regardless of what those digits look like, got ${local.guest_hostname_containers["baz-540"]}"
  }
}

run "ansible_inventory_hostnames_match_the_generated_names" {
  command = plan

  variables {
    containers = {
      "llm-router-1" = {
        node_name = "node-alpha"
        vm_id     = 301080
        vlan      = "apps"
        dhcp      = true
      }
    }
    vms = {
      "docker-host-540" = {
        node_name = "node-alpha"
        vm_id     = 301090
        vlan      = "apps"
        dhcp      = true
      }
    }
  }

  assert {
    condition     = output.ansible_inventory.containers["llm-router-1"].hostname == local.guest_hostname_containers["llm-router-1"]
    error_message = "the published container hostname must equal the generated name, got ${output.ansible_inventory.containers["llm-router-1"].hostname}"
  }

  assert {
    condition     = output.ansible_inventory.vms["docker-host-540"].hostname == local.guest_hostname_vms["docker-host-540"]
    error_message = "the published VM hostname must equal the generated name, got ${output.ansible_inventory.vms["docker-host-540"].hostname}"
  }
}
