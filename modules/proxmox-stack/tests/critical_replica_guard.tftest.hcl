# Tests for the critical-guest failover-replica guard (checks-critical-replica.tf).
#
# A guest marked critical = true must survive the loss of its own node: ha
# enrolment plus a replica on another node, or an affinity group with a second
# ha-enrolled member. Each case plans ONLY the guard resource, so no other
# guard's precondition can mask or add to the result (same convention as
# node_memory_capacity_guard.tftest.hcl).
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
    mac_address = "00:00:5E:00:53:C8"
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
  proxmox_user            = "root"
  proxmox_ssh_private_key = "-----BEGIN OPENSSH PRIVATE KEY-----\ntest\n-----END OPENSSH PRIVATE KEY-----"
  network_cidrs           = { for name, id in var.vlan_ids : name => "192.168.${id}.0/24" }
}

# --- Must-pass shapes --------------------------------------------------------

run "critical_guest_with_replica_on_another_node_passes" {
  command = plan
  plan_options { target = [terraform_data.critical_replica_guard] }

  variables {
    containers = {
      guest-one = {
        vm_id                 = 101
        node_name             = "node-a"
        vlan                  = "data"
        critical              = true
        ha                    = true
        ha_replication_target = "node-b"
      }
    }
  }

  assert {
    condition     = length(local.critical_guests_without_replica) == 0
    error_message = "A critical guest with ha and a replica on another node must pass, got: ${join(", ", local.critical_guests_without_replica)}"
  }
}

run "critical_guests_sharing_an_affinity_group_pass_without_replicas" {
  command = plan
  plan_options { target = [terraform_data.critical_replica_guard] }

  variables {
    containers = {
      guest-one = {
        vm_id             = 104
        node_name         = "node-a"
        vlan              = "data"
        critical          = true
        ha                = true
        ha_affinity_group = "group-one"
      }
      guest-two = {
        vm_id             = 105
        node_name         = "node-b"
        vlan              = "data"
        critical          = true
        ha                = true
        ha_affinity_group = "group-one"
      }
    }
  }

  assert {
    condition     = length(local.critical_guests_without_replica) == 0
    error_message = "Two critical guests sharing one affinity group must pass without replica targets, got: ${join(", ", local.critical_guests_without_replica)}"
  }
}

run "non_critical_guest_without_ha_still_passes" {
  command = plan
  plan_options { target = [terraform_data.critical_replica_guard] }

  variables {
    containers = {
      guest-one = {
        vm_id     = 106
        node_name = "node-a"
        vlan      = "data"
      }
    }
  }

  assert {
    condition     = length(local.critical_guests_without_replica) == 0
    error_message = "A guest without the critical flag must not be judged by this guard at all."
  }
}

# --- Must-fail shapes --------------------------------------------------------

run "critical_guest_without_replica_target_fails" {
  command = plan
  plan_options { target = [terraform_data.critical_replica_guard] }

  variables {
    containers = {
      guest-one = {
        vm_id     = 102
        node_name = "node-a"
        vlan      = "data"
        critical  = true
        ha        = true
      }
    }
  }

  expect_failures = [terraform_data.critical_replica_guard]
}

run "critical_guest_replicating_to_its_own_node_fails" {
  command = plan
  plan_options { target = [terraform_data.critical_replica_guard] }

  variables {
    containers = {
      guest-one = {
        vm_id                 = 103
        node_name             = "node-a"
        vlan                  = "data"
        critical              = true
        ha                    = true
        ha_replication_target = "node-a"
      }
    }
  }

  expect_failures = [terraform_data.critical_replica_guard]
}
