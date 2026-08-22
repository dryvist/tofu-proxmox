# Tests for the container-datastore guard (checks-storage.tf).
#
# Each case gets BOTH a must-fail and a must-pass control, per the convention in
# node_storage_smb.tftest.hcl. A negative test alone cannot tell a working guard
# from one that rejects everything, and a positive test alone cannot tell a
# working guard from one that is never evaluated. That distinction is the whole
# reason this guard exists — the defect it catches was invisible precisely
# because nothing ever evaluated the declaration.
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

  # Two nodes with DIFFERENT registered pools. This is the shape that produced
  # the real defect: `fast` exists in the cluster, but only on one node, so a
  # guest elsewhere naming it looks plausible and resolves to something else.
  node_storage = {
    node-with-fast = {
      pools = {
        fast = { register = true }
      }
    }
    node-without-fast = {
      pools = {
        bulk = { register = true }
        # Declared so its properties are managed, but never exposed to PVE as a
        # datastore — so it must NOT count as a usable target.
        rpool = { register = false }
      }
    }
  }
}

# --- Positive controls -------------------------------------------------------

run "mount_on_a_pool_registered_on_that_node_is_accepted" {
  command = plan

  variables {
    containers = {
      db = {
        node_name    = "node-with-fast"
        vm_id        = 519000
        hostname     = "db"
        vlan         = "data"
        dhcp         = true
        mount_points = [{ volume = "fast", size = "40G", path = "/var/lib/postgresql" }]
      }
    }
  }

  assert {
    condition     = length(local.invalid_container_datastore_refs) == 0
    error_message = "a mount on a pool registered on its own node must pass, got: ${join("; ", local.invalid_container_datastore_messages)}"
  }
}

run "builtin_datastores_are_accepted_without_being_declared" {
  command = plan

  variables {
    containers = {
      # local and local-zfs exist on every PVE node and never appear in
      # node_storage.pools. Rejecting them would fail most of the estate.
      a = {
        node_name    = "node-without-fast"
        vm_id        = 100
        hostname     = "a"
        vlan         = "data"
        dhcp         = true
        root_disk    = { datastore_id = "local-zfs", size = 16 }
        mount_points = [{ volume = "local-zfs", size = "10G", path = "/data" }]
      }
      b = {
        node_name = "node-without-fast"
        vm_id     = 101
        hostname  = "b"
        vlan      = "data"
        dhcp      = true
        root_disk = { datastore_id = "local", size = 16 }
      }
    }
  }

  assert {
    condition     = length(local.invalid_container_datastore_refs) == 0
    error_message = "built-in datastores must be accepted, got: ${join("; ", local.invalid_container_datastore_messages)}"
  }
}

run "host_bind_mount_is_exempt" {
  command = plan

  variables {
    containers = {
      # No `size` means `volume` is a host PATH, not a datastore id. Judging it
      # as a datastore would reject every bind-mount in the estate.
      media = {
        node_name    = "node-without-fast"
        vm_id        = 102
        hostname     = "media"
        vlan         = "data"
        dhcp         = true
        mount_points = [{ volume = "/bulk/data", path = "/mnt/data" }]
      }
    }
  }

  assert {
    condition     = length(local.invalid_container_datastore_refs) == 0
    error_message = "host bind-mounts must be exempt, got: ${join("; ", local.invalid_container_datastore_messages)}"
  }
}

run "container_on_a_node_absent_from_node_storage_is_not_judged" {
  command = plan

  variables {
    containers = {
      elsewhere = {
        node_name    = "undeclared-node"
        vm_id        = 104
        hostname     = "elsewhere"
        vlan         = "data"
        dhcp         = true
        mount_points = [{ volume = "anything", size = "5G", path = "/srv" }]
      }
    }
  }

  assert {
    condition     = length(local.invalid_container_datastore_refs) == 0
    error_message = "a node with no declared storage has nothing to compare against and must not be judged"
  }
}

# --- Must-fail cases ---------------------------------------------------------

run "mount_on_a_pool_registered_on_another_node_is_rejected" {
  command = plan

  variables {
    containers = {
      # THE REAL DEFECT: `fast` is a real pool, on a different node. Proxmox
      # accepts this and silently places the volume elsewhere.
      db = {
        node_name    = "node-without-fast"
        vm_id        = 519000
        hostname     = "db"
        vlan         = "data"
        dhcp         = true
        mount_points = [{ volume = "fast", size = "40G", path = "/var/lib/postgresql" }]
      }
    }
  }

  expect_failures = [
    terraform_data.container_datastore_guard,
  ]
}

run "root_disk_on_a_pool_registered_on_another_node_is_rejected" {
  command = plan

  variables {
    containers = {
      db = {
        node_name = "node-without-fast"
        vm_id     = 519001
        hostname  = "db2"
        vlan      = "data"
        dhcp      = true
        root_disk = { datastore_id = "fast", size = 16 }
      }
    }
  }

  expect_failures = [
    terraform_data.container_datastore_guard,
  ]
}

run "unregistered_pool_is_rejected_even_though_it_is_declared" {
  command = plan

  variables {
    containers = {
      # rpool IS declared on this node, but with register = false, so PVE never
      # exposes it as a datastore. Declared is not the same as usable.
      db = {
        node_name    = "node-without-fast"
        vm_id        = 519002
        hostname     = "db3"
        vlan         = "data"
        dhcp         = true
        mount_points = [{ volume = "rpool", size = "8G", path = "/srv" }]
      }
    }
  }

  expect_failures = [
    terraform_data.container_datastore_guard,
  ]
}
