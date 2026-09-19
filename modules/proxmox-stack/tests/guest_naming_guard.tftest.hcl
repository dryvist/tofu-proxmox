# Tests for the guest-naming guard (checks-guest-naming.tf).
#
# The law: a guest name is `<app>` or `<app>-<n>`, where `<n>` is a 1-2 digit
# ordinal and, for each `<app>`, the ordinals in use are exactly `1..N` with
# no gaps or duplicates. Placement is never encoded, so `ha = true` no longer
# changes what is accepted — every guest is judged the same way.
#
# Every case gets BOTH a must-pass and a must-fail control, per the
# convention in container_datastore_guard.tftest.hcl: a negative test alone
# cannot tell a working guard from one that rejects everything, and a
# positive test alone cannot tell a working guard from one that is never
# evaluated.
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
    node-beta  = { role = "node-2" }
  }
}

# --- Positive controls -------------------------------------------------------

run "bare_name_single_instance_is_accepted" {
  command = plan

  variables {
    containers = {
      foo = {
        node_name = "node-alpha"
        vm_id     = 601000
        hostname  = "foo"
        vlan      = "apps"
        dhcp      = true
      }
    }
  }

  assert {
    condition     = length(local.guest_naming_failures) == 0
    error_message = "a bare single-instance name must pass, got: ${join("; ", local.guest_naming_failures)}"
  }
}

run "contiguous_ordinals_are_accepted" {
  command = plan

  variables {
    containers = {
      foo-1 = {
        node_name = "node-alpha"
        vm_id     = 601001
        hostname  = "foo-1"
        vlan      = "apps"
        dhcp      = true
      }
      foo-2 = {
        node_name = "node-beta"
        vm_id     = 601002
        hostname  = "foo-2"
        vlan      = "apps"
        dhcp      = true
      }
    }
  }

  assert {
    condition     = length(local.guest_naming_failures) == 0
    error_message = "instances 1..N with no gaps must pass, got: ${join("; ", local.guest_naming_failures)}"
  }
}

run "relocatable_guest_with_an_ordinal_is_accepted" {
  command = plan

  variables {
    containers = {
      # Placement is never encoded, so ha = true no longer changes what is
      # accepted — a relocatable guest is judged exactly like a pinned one.
      foo-1 = {
        node_name = "node-alpha"
        vm_id     = 601003
        hostname  = "foo-1"
        vlan      = "apps"
        dhcp      = true
        ha        = true
      }
    }
  }

  assert {
    condition     = length(local.guest_naming_failures) == 0
    error_message = "a relocatable guest with a valid ordinal must pass, got: ${join("; ", local.guest_naming_failures)}"
  }
}

run "allowlisted_pre_law_name_is_accepted" {
  command = plan

  variables {
    containers = {
      # A 5-digit tail fails the ordinal rule outright. Exempt only because
      # it is named in the (private, here test-supplied) allowlist.
      technitium-50000 = {
        node_name = "node-alpha"
        vm_id     = 501000
        hostname  = "technitium-50000"
        vlan      = "ai"
        dhcp      = true
      }
    }
    guest_naming_exceptions = {
      technitium-50000 = "pre-law name awaiting a planned rename"
    }
  }

  assert {
    condition     = length(local.guest_naming_failures) == 0
    error_message = "an allowlisted pre-law name must pass, got: ${join("; ", local.guest_naming_failures)}"
  }
}

run "vm_names_are_judged_too" {
  command = plan

  variables {
    vms = {
      splunk-idx-1 = {
        node_name = "node-beta"
        vm_id     = 421100
        name      = "splunk-idx-1"
        vlan      = "siem"
        dhcp      = true
      }
    }
  }

  assert {
    condition     = length(local.guest_naming_failures) == 0
    error_message = "a VM with a valid ordinal must pass, got: ${join("; ", local.guest_naming_failures)}"
  }
}

# --- Must-fail cases ---------------------------------------------------------

run "gap_in_ordinals_is_rejected" {
  command = plan

  variables {
    containers = {
      # foo-2 with no foo-1: a suffix must mean instance n of N, and N=1 here.
      foo-2 = {
        node_name = "node-alpha"
        vm_id     = 601004
        hostname  = "foo-2"
        vlan      = "apps"
        dhcp      = true
      }
    }
  }

  expect_failures = [
    terraform_data.guest_naming_guard,
  ]
}

run "leading_zero_ordinal_is_rejected" {
  command = plan

  variables {
    containers = {
      foo-01 = {
        node_name = "node-alpha"
        vm_id     = 601005
        hostname  = "foo-01"
        vlan      = "apps"
        dhcp      = true
      }
    }
  }

  expect_failures = [
    terraform_data.guest_naming_guard,
  ]
}

run "zero_ordinal_is_rejected" {
  command = plan

  variables {
    containers = {
      foo-0 = {
        node_name = "node-alpha"
        vm_id     = 601006
        hostname  = "foo-0"
        vlan      = "apps"
        dhcp      = true
      }
    }
  }

  expect_failures = [
    terraform_data.guest_naming_guard,
  ]
}

run "three_digit_ordinal_is_rejected" {
  command = plan

  variables {
    containers = {
      foo-123 = {
        node_name = "node-alpha"
        vm_id     = 601007
        hostname  = "foo-123"
        vlan      = "apps"
        dhcp      = true
      }
    }
  }

  expect_failures = [
    terraform_data.guest_naming_guard,
  ]
}

run "unlisted_three_digit_ordinal_is_rejected" {
  command = plan

  variables {
    containers = {
      # A 3-digit tail fails the ordinal rule outright and is not on the
      # (empty, in this run) exception list.
      foo-501 = {
        node_name = "node-alpha"
        vm_id     = 601008
        hostname  = "foo-501"
        vlan      = "apps"
        dhcp      = true
      }
    }
  }

  expect_failures = [
    terraform_data.guest_naming_guard,
  ]
}

run "hardware_token_suffix_is_rejected" {
  command = plan

  variables {
    containers = {
      # A GPU model number is a 4-digit tail — the same ordinal-length rule
      # that rejects "-501" rejects a hardware token, no separate check
      # needed.
      llm-4080 = {
        node_name = "node-alpha"
        vm_id     = 601009
        hostname  = "llm-4080"
        vlan      = "ai"
        dhcp      = true
      }
    }
  }

  expect_failures = [
    terraform_data.guest_naming_guard,
  ]
}
