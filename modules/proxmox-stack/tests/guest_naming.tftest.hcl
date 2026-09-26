# Tests for generated guest naming (locals-guest-naming.tf:
# guest_hostname_containers / guest_hostname_vms).
#
# Rule under test: a desired-state entry that OMITS hostname/name gets the
# generated form "<app>-<vm_id>" (app = the map key with any trailing
# "-<digits>" stripped); one that DECLARES it keeps that value verbatim —
# no guard, no exception list, just "declared beats generated". See
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
  network_cidrs           = { for name, id in var.vlan_ids : name => "192.168.${id}.0/24" }
  vm_ssh_public_key       = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestKeyData test@test"
  proxmox_user            = "root"
  proxmox_ssh_private_key = "-----BEGIN OPENSSH PRIVATE KEY-----\ntest\n-----END OPENSSH PRIVATE KEY-----"

  nodes = {
    node-alpha = { role = "node-1" }
  }
}

run "container_omitting_hostname_generates_key_dash_vmid_6_digit" {
  command = plan

  variables {
    containers = {
      foo = {
        node_name = "node-alpha"
        vm_id     = 301050
        vlan      = "apps"
        dhcp      = true
      }
    }
  }

  assert {
    condition     = local.guest_hostname_containers["foo"] == "foo-301050"
    error_message = "an entry omitting hostname must generate <key>-<vm_id> (6-digit), got ${local.guest_hostname_containers["foo"]}"
  }
}

run "container_omitting_hostname_generates_key_dash_vmid_7_digit" {
  command = plan

  variables {
    containers = {
      bar = {
        node_name = "node-alpha"
        vm_id     = 3010500
        vlan      = "apps"
        dhcp      = true
      }
    }
  }

  assert {
    condition     = local.guest_hostname_containers["bar"] == "bar-3010500"
    error_message = "an entry omitting hostname must generate <key>-<vm_id> (7-digit), got ${local.guest_hostname_containers["bar"]}"
  }
}

run "container_key_with_trailing_digit_strips_it_from_the_app" {
  command = plan

  variables {
    containers = {
      "baz-2" = {
        node_name = "node-alpha"
        vm_id     = 301060
        vlan      = "apps"
        dhcp      = true
      }
    }
  }

  assert {
    condition     = local.guest_hostname_containers["baz-2"] == "baz-301060"
    error_message = "a key with a trailing numeric suffix must strip it before appending vm_id, got ${local.guest_hostname_containers["baz-2"]}"
  }
}

run "container_key_already_shaped_app_dash_vmid_round_trips" {
  command = plan

  # A key already shaped "<app>-<vm_id>" round-trips unchanged, because
  # stripping the trailing "-<vm_id>" and re-appending it is a no-op. (The
  # openbao/node-service generators do NOT emit keys in this shape today —
  # they keep the ordinal "<prefix><NN>" form for a live-guest-identity
  # reason documented in docs/GUEST_NAMING.md — this only exercises the
  # shared local's general behavior.)
  variables {
    containers = {
      "openbao-110010" = {
        node_name = "node-alpha"
        vm_id     = 110010
        vlan      = "apps"
        dhcp      = true
      }
    }
  }

  assert {
    condition     = local.guest_hostname_containers["openbao-110010"] == "openbao-110010"
    error_message = "a generator-shaped key must round-trip to the same generated hostname, got ${local.guest_hostname_containers["openbao-110010"]}"
  }
}

run "container_declaring_hostname_keeps_it_unchanged" {
  command = plan

  # An EXISTING guest: declares its live hostname, which does not match what
  # the generator would produce from this key/vm_id. It must be kept exactly
  # as declared until its own rename wave — no guard, no exception list.
  variables {
    containers = {
      legacy = {
        node_name = "node-alpha"
        vm_id     = 301070
        hostname  = "some-legacy-name"
        vlan      = "apps"
        dhcp      = true
      }
    }
  }

  assert {
    condition     = local.guest_hostname_containers["legacy"] == "some-legacy-name"
    error_message = "a declared hostname must be kept verbatim, got ${local.guest_hostname_containers["legacy"]}"
  }
}

run "vm_omitting_name_generates_key_dash_vmid" {
  command = plan

  variables {
    vms = {
      qux = {
        node_name = "node-alpha"
        vm_id     = 4010500
        vlan      = "apps"
        dhcp      = true
      }
    }
  }

  assert {
    condition     = local.guest_hostname_vms["qux"] == "qux-4010500"
    error_message = "a VM entry omitting name must generate <key>-<vm_id>, got ${local.guest_hostname_vms["qux"]}"
  }
}

run "vm_declaring_name_keeps_it_unchanged" {
  command = plan

  variables {
    vms = {
      legacy-vm = {
        node_name = "node-alpha"
        vm_id     = 401060
        name      = "some-legacy-vm-name"
        vlan      = "apps"
        dhcp      = true
      }
    }
  }

  assert {
    condition     = local.guest_hostname_vms["legacy-vm"] == "some-legacy-vm-name"
    error_message = "a declared VM name must be kept verbatim, got ${local.guest_hostname_vms["legacy-vm"]}"
  }
}
