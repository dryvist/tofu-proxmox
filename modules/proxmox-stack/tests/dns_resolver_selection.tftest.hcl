# Tests for local.dns_servers — which containers become guest resolvers.
#
# Every guest receives this WHOLE list and its stub resolver fails over between
# entries natively. That is the reason resolvers hold unique addresses and never
# share one, so the selector has to pick up a new resolver on sight: an instance
# silently left out of the list can only be reached by taking over an address
# already in it, which is the anti-pattern these tests exist to keep out.
#
# Selection is by the `dns` tag. The previous `^technitium-dns` name prefix could
# not see an instance named under the current law (app name, host digit, instance
# counter, no hyphen) — the regression pinned by new_law_name_is_selected below.
#
# Addresses here are RFC 5737 documentation space (192.0.2.0/24), not the estate's
# fixture convention, so nothing resembling a real host address is committed. Every
# VLAN maps to the same documentation range because these runs only ever place
# containers on one VLAN; the cidrhost() math is exercised identically.

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
    name        = "splunk-vm"
    ip_address  = "192.0.2.200"
    mac_address = "BC:24:11:00:00:C8"
    tiered_disks = {
      fast = { datastore_id = "fast-splunk", interface = "virtio2", size = 1024, backup = true }
      bulk = { datastore_id = "bulk-splunk", interface = "virtio3", size = 2048, backup = false }
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

variables {
  network_cidrs     = { for name, id in var.vlan_ids : name => "192.0.2.0/24" }
  vm_ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestKeyData test@test"
  # Deliberately NOT key-shaped. The variable's validation only requires a
  # leading -----BEGIN, so a placeholder satisfies it without committing a
  # string that pattern-matches real private-key material.
  proxmox_ssh_private_key = "-----BEGIN TEST PLACEHOLDER-----\nnot-key-material\n-----END TEST PLACEHOLDER-----"
}

# The case the name-prefix selector got wrong. A resolver named under the current
# law carries no "-dns" substring, so the old regex dropped it from every guest's
# resolver list without erroring — invisible until someone noticed nothing could
# reach it. Tagged, it is selected regardless of what it is called.
run "new_law_name_is_selected" {
  command = plan

  variables {
    containers = {
      "technitium-dns" = {
        vm_id = 103, hostname = "technitium-dns", vlan = "dns"
        tags  = ["container", "dns", "terraform"]
      }
      "technitium30" = {
        vm_id = 104, hostname = "technitium30", vlan = "dns"
        tags  = ["container", "dns", "terraform"]
      }
    }
  }

  assert {
    condition     = contains(local.dns_servers, "192.0.2.104")
    error_message = "a resolver named under the current law must be selected; the old ^technitium-dns prefix silently dropped it, and an unreachable resolver is what makes taking over another instance's address look like the fix"
  }

  assert {
    condition     = length(local.dns_servers) == 2
    error_message = "both tagged resolvers must appear, got ${length(local.dns_servers)}"
  }
}

# Legacy names keep working through the migration — the tag is what selects, so
# renaming an instance neither adds nor drops it.
run "legacy_names_still_selected" {
  command = plan

  variables {
    containers = {
      "technitium-dns" = {
        vm_id = 103, hostname = "technitium-dns", vlan = "dns"
        tags  = ["container", "dns", "terraform"]
      }
      "technitium-dns-2" = {
        vm_id = 105, hostname = "technitium-dns-2", vlan = "dns"
        tags  = ["container", "dns", "terraform"]
      }
    }
  }

  assert {
    condition = alltrue([
      contains(local.dns_servers, "192.0.2.103"),
      contains(local.dns_servers, "192.0.2.105"),
    ])
    error_message = "legacy-named resolvers must still be selected during the rename migration"
  }
}

# An untagged container is not a resolver, however it is named. Guards the
# mirror-image failure of the old prefix: selecting something by accident.
run "untagged_container_is_not_a_resolver" {
  command = plan

  variables {
    containers = {
      "technitium-dns" = {
        vm_id = 103, hostname = "technitium-dns", vlan = "dns"
        tags  = ["container", "dns", "terraform"]
      }
      # Named to look like a resolver, deliberately untagged.
      "technitium-docs" = {
        vm_id = 106, hostname = "technitium-docs", vlan = "dns"
        tags  = ["container", "terraform"]
      }
    }
  }

  assert {
    condition     = local.dns_servers == ["192.0.2.103"]
    error_message = "only tagged resolvers belong in the list, got ${jsonencode(local.dns_servers)}"
  }
}

# The standing rule, encoded: resolvers never share an address. Two entries
# collapsing to one value means a standby was pinned onto a live instance's IP,
# which the client-side list exists specifically to avoid needing.
run "resolver_addresses_are_unique" {
  command = plan

  variables {
    containers = {
      "technitium-dns" = {
        vm_id = 103, hostname = "technitium-dns", vlan = "dns"
        tags  = ["container", "dns", "terraform"]
      }
      "technitium30" = {
        vm_id = 104, hostname = "technitium30", vlan = "dns"
        tags  = ["container", "dns", "terraform"]
      }
      "technitium40" = {
        vm_id = 107, hostname = "technitium40", vlan = "dns"
        tags  = ["container", "dns", "terraform"]
      }
    }
  }

  assert {
    condition     = length(distinct(local.dns_servers)) == length(local.dns_servers)
    error_message = "resolvers must hold unique addresses — a duplicate means a standby was pinned onto another instance's IP: ${jsonencode(local.dns_servers)}"
  }
}
