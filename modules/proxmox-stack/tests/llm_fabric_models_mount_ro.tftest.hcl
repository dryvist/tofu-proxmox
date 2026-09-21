# Does the stack derive read_only for the llm fabric's shared models mount,
# without requiring a per-guest literal in the desired state?
#
# The llama_cpp Ansible role (roles/llama_cpp/tasks/main.yml in
# ansible-proxmox-ai) asserts var.llm_models_mount_path is mounted `ro` before
# it will deploy the serving unit. modules/proxmox-container now supports a
# read_only mount_point attribute, but nothing set it — this test proves the
# stack sets it FOR the fabric, from ONE base variable + tag membership
# (local.llm_fast_container_ids), rather than three separate JSON edits.
#
# Every case gets a positive and a negative control, per the convention in
# container_datastore_guard.tftest.hcl: a positive alone can't tell a working
# derivation from one that marks everything read-only, and a negative alone
# can't tell it from one that never runs.

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
  node_storage            = {}
}

# --- Positive: an llm-fabric LXC's models mount gets read_only derived ------

run "fabric_models_mount_is_derived_read_only" {
  command = plan

  variables {
    containers = {
      "llm-fast" = {
        node_name = "proxmox-1"
        vm_id     = 610000
        hostname  = "llm-fast"
        vlan      = "ai"
        dhcp      = true
        tags      = ["llm-fast"]
        mount_points = [
          { volume = "/models-pool/llama-cpp", path = "/var/lib/llm" },
        ]
      }
    }
  }

  assert {
    condition     = module.containers[0].container_mount_points["llm-fast"]["/var/lib/llm"] == true
    error_message = "an llm-fabric LXC's models mount did not derive read_only — the llama_cpp role's mount assert would still fail."
  }
}

# --- Negative control 1: a non-fabric LXC's data mount stays writable -------

run "non_fabric_mount_stays_writable" {
  command = plan

  variables {
    containers = {
      db = {
        node_name = "proxmox-1"
        vm_id     = 610001
        hostname  = "db"
        vlan      = "data"
        dhcp      = true
        mount_points = [
          { volume = "/data-pool/example", path = "/data" },
        ]
      }
    }
  }

  assert {
    condition     = module.containers[0].container_mount_points["db"]["/data"] == false
    error_message = "a non-fabric guest's mount was marked read_only — the derivation is not scoped to the llm fabric and would break every other guest's writable mount."
  }
}

# --- Negative control 2: an llm-fabric LXC's OTHER mount stays writable -----

run "fabric_guest_non_models_mount_stays_writable" {
  command = plan

  variables {
    containers = {
      "llm-fast" = {
        node_name = "proxmox-1"
        vm_id     = 610002
        hostname  = "llm-fast"
        vlan      = "ai"
        dhcp      = true
        tags      = ["llm-fast"]
        mount_points = [
          { volume = "/scratch-pool/example", path = "/var/lib/llama-cpp/scratch" },
        ]
      }
    }
  }

  assert {
    condition     = module.containers[0].container_mount_points["llm-fast"]["/var/lib/llama-cpp/scratch"] == false
    error_message = "the derivation matched on fabric tag alone, ignoring path — an llm fabric guest's unrelated mount was marked read_only."
  }
}

# --- Explicit override wins ---------------------------------------------------

run "explicit_false_overrides_the_fabric_derivation" {
  command = plan

  variables {
    containers = {
      "llm-fast" = {
        node_name = "proxmox-1"
        vm_id     = 610003
        hostname  = "llm-fast"
        vlan      = "ai"
        dhcp      = true
        tags      = ["llm-fast"]
        mount_points = [
          { volume = "/models-pool/llama-cpp", path = "/var/lib/llm", read_only = false },
        ]
      }
    }
  }

  assert {
    condition     = module.containers[0].container_mount_points["llm-fast"]["/var/lib/llm"] == false
    error_message = "an explicit read_only = false in the desired state was overridden by the fabric derivation."
  }
}
