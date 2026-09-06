# Tests for the guest-naming guard (checks-guest-naming.tf).
#
# Every case gets BOTH a must-pass and a must-fail control, per the convention
# in container_datastore_guard.tftest.hcl: a negative test alone cannot tell a
# working guard from one that rejects everything, and a positive test alone
# cannot tell a working guard from one that is never evaluated.
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

  # Two nodes whose logical digits are NOT their ordinal position, so a test
  # that passes by coincidence (digit == "1" for the first node) cannot.
  nodes = {
    node-alpha = { role = "node-1", logical_id = 5 }
    node-beta  = { role = "node-2", logical_id = 7 }
    # Declares no logical_id: opted out, and guests on it are not judged.
    node-unmapped = { role = "node-3" }
  }
}

# --- Positive controls -------------------------------------------------------

run "matching_node_digit_is_accepted" {
  command = plan

  variables {
    containers = {
      technitium-50 = {
        node_name = "node-alpha"
        vm_id     = 5310050
        hostname  = "technitium-50"
        vlan      = "dns"
        dhcp      = true
      }
      technitium-70 = {
        node_name = "node-beta"
        vm_id     = 5310070
        hostname  = "technitium-70"
        vlan      = "dns"
        dhcp      = true
      }
    }
  }

  assert {
    condition     = length(local.guest_naming_failures) == 0
    error_message = "a pinned guest whose digit matches its node must pass, got: ${join("; ", local.guest_naming_failures)}"
  }
}

run "guest_with_no_numeric_suffix_is_accepted" {
  command = plan

  variables {
    containers = {
      # The relocatable shape: a singleton that depends on HA migration, so it
      # encodes no node at all.
      vikunja = {
        node_name = "node-alpha"
        vm_id     = 601000
        hostname  = "vikunja"
        vlan      = "apps"
        dhcp      = true
        ha        = true
      }
    }
  }

  assert {
    condition     = length(local.guest_naming_failures) == 0
    error_message = "a relocatable guest with no node digit must pass, got: ${join("; ", local.guest_naming_failures)}"
  }
}

run "guest_on_a_node_without_a_logical_id_is_not_judged" {
  command = plan

  variables {
    containers = {
      # Digit 9 matches no declared node, and the suffix is the wrong length —
      # but the node opts out, so there is nothing to compare against.
      whatever-9 = {
        node_name = "node-unmapped"
        vm_id     = 601001
        hostname  = "whatever-9"
        vlan      = "apps"
        dhcp      = true
      }
    }
  }

  assert {
    condition     = length(local.guest_naming_failures) == 0
    error_message = "a node with no logical_id has nothing to compare against and must not be judged"
  }
}

run "allowlisted_pre_law_name_is_accepted" {
  command = plan

  variables {
    containers = {
      # Single-digit suffix, and the digit matches no node. Exempt only because
      # it is named in the tracked allowlist.
      llm-router-1 = {
        node_name = "node-alpha"
        vm_id     = 501000
        hostname  = "llm-router-1"
        vlan      = "ai"
        dhcp      = true
      }
    }
  }

  assert {
    condition     = length(local.guest_naming_failures) == 0
    error_message = "an allowlisted pre-law name must pass, got: ${join("; ", local.guest_naming_failures)}"
  }
}

# --- Must-fail cases ---------------------------------------------------------

run "single_digit_suffix_is_rejected" {
  command = plan

  variables {
    containers = {
      technitium-5 = {
        node_name = "node-alpha"
        vm_id     = 5310051
        hostname  = "technitium-5"
        vlan      = "dns"
        dhcp      = true
      }
    }
  }

  expect_failures = [
    terraform_data.guest_naming_guard,
  ]
}

run "node_digit_that_does_not_match_the_node_is_rejected" {
  command = plan

  variables {
    containers = {
      # The failure this guard exists for: a name that was true on the node the
      # guest was built on and has been lying since it was evacuated.
      technitium-50 = {
        node_name = "node-beta"
        vm_id     = 5310052
        hostname  = "technitium-50"
        vlan      = "dns"
        dhcp      = true
      }
    }
  }

  expect_failures = [
    terraform_data.guest_naming_guard,
  ]
}

run "relocatable_guest_carrying_a_node_digit_is_rejected" {
  command = plan

  variables {
    containers = {
      vikunja-50 = {
        node_name = "node-alpha"
        vm_id     = 601002
        hostname  = "vikunja-50"
        vlan      = "apps"
        dhcp      = true
        ha        = true
      }
    }
  }

  expect_failures = [
    terraform_data.guest_naming_guard,
  ]
}

run "vm_names_are_judged_too" {
  command = plan

  variables {
    vms = {
      splunk-idx-50 = {
        node_name = "node-beta"
        vm_id     = 421100
        name      = "splunk-idx-50"
        vlan      = "siem"
        dhcp      = true
      }
    }
  }

  expect_failures = [
    terraform_data.guest_naming_guard,
  ]
}

run "two_nodes_claiming_the_same_logical_id_is_rejected" {
  command = plan

  variables {
    nodes = {
      node-alpha = { role = "node-1", logical_id = 5 }
      node-beta  = { role = "node-2", logical_id = 5 }
    }
  }

  expect_failures = [
    terraform_data.guest_naming_guard,
  ]
}
