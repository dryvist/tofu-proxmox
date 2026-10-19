variables {
  proxmox_user            = "root"
  proxmox_ssh_private_key = "-----BEGIN OPENSSH PRIVATE KEY-----\ntest\n-----END OPENSSH PRIVATE KEY-----"
  vm_ssh_public_key       = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestKeyData test@test"
  network_cidrs           = { for name, id in var.vlan_ids : name => "192.168.${id}.0/24" }
  nodes                   = { compute-a = { role = "compute", tags = ["nvidia-gpu"] } }
}

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
  target  = module.storage
  outputs = { cloud_init_file_id = null, datastores_available = {}, storage_validated = true }
}

override_module {
  target = module.splunk_vm
  outputs = {
    vm_id      = 200
    name       = "splunk-vm"
    ip_address = "192.0.2.200"
    tiered_disks = {
      fast = { datastore_id = "fast-splunk", interface = "virtio2", size = 1024, backup = true }
      bulk = { datastore_id = "bulk-splunk", interface = "virtio3", size = 2048, backup = false }
    }
  }
}

override_module {
  target  = module.firewall
  outputs = { cluster_firewall_enabled = true, vm_firewall_enabled = true, container_firewall_enabled = true, pipeline_container_firewall_enabled = true }
}

override_module {
  target  = module.acme_certificates
  outputs = { acme_accounts = {}, dns_plugins = {}, certificates = {} }
}

run "strata_engine_guest_is_stopped_by_default" {
  command = plan

  variables {
    containers = {
      llama = {
        hostname                = "llm-ada-lovelace-6-24GB-engine-a"
        vm_id                   = 610021
        node_name               = "compute-a"
        vlan                    = "ai"
        dhcp                    = true
        tags                    = ["gpu-passthrough"]
        llm_gpu_engine_identity = "llama_cpp"
      }
      vllm = {
        hostname                = "llm-ada-lovelace-6-24GB-engine-b"
        vm_id                   = 610022
        node_name               = "compute-a"
        vlan                    = "ai"
        dhcp                    = true
        tags                    = ["gpu-passthrough"]
        llm_gpu_engine_identity = "vllm"
      }
      strata = {
        hostname                = "llm-ada-lovelace-6-24GB-engine-c"
        vm_id                   = 610024
        node_name               = "compute-a"
        vlan                    = "ai"
        dhcp                    = true
        tags                    = ["gpu-passthrough"]
        llm_gpu_engine_identity = "strata"
      }
      legacy = {
        hostname      = "llm-ada-lovelace-6-24GB-legacy"
        vm_id         = 610023
        node_name     = "compute-a"
        vlan          = "ai"
        dhcp          = true
        tags          = ["llm-gpu", "gpu-passthrough"]
        started       = true
        start_on_boot = true
      }
    }
  }

  assert {
    condition = (
      output.ansible_inventory.containers["strata"].started == false &&
      output.ansible_inventory.containers["strata"].start_on_boot == false
    )
    error_message = "The Strata guest must be stopped and disabled at boot under the default selector."
  }
}

run "strata_selector_requires_only_its_guest_to_be_running" {
  command = plan

  variables {
    llm_gpu_engine = "strata"
    containers = {
      llama = {
        hostname                = "llm-ada-lovelace-6-24GB-engine-a"
        vm_id                   = 610021
        node_name               = "compute-a"
        vlan                    = "ai"
        dhcp                    = true
        tags                    = ["gpu-passthrough"]
        llm_gpu_engine_identity = "llama_cpp"
      }
      vllm = {
        hostname                = "llm-ada-lovelace-6-24GB-engine-b"
        vm_id                   = 610022
        node_name               = "compute-a"
        vlan                    = "ai"
        dhcp                    = true
        tags                    = ["gpu-passthrough"]
        llm_gpu_engine_identity = "vllm"
      }
      strata = {
        hostname                = "llm-ada-lovelace-6-24GB-engine-c"
        vm_id                   = 610024
        node_name               = "compute-a"
        vlan                    = "ai"
        dhcp                    = true
        tags                    = ["gpu-passthrough"]
        llm_gpu_engine_identity = "strata"
      }
      companion = {
        hostname      = "example-companion"
        vm_id         = 610025
        node_name     = "compute-a"
        vlan          = "ai"
        dhcp          = true
        started       = false
        start_on_boot = false
      }
      legacy = {
        hostname      = "llm-ada-lovelace-6-24GB-legacy"
        vm_id         = 610023
        node_name     = "compute-a"
        vlan          = "ai"
        dhcp          = true
        tags          = ["llm-gpu", "gpu-passthrough"]
        started       = true
        start_on_boot = true
      }
    }
  }

  assert {
    condition = (
      output.ansible_inventory.containers["strata"].started == true &&
      output.ansible_inventory.containers["strata"].start_on_boot == true &&
      output.ansible_inventory.containers["llama"].started == false &&
      output.ansible_inventory.containers["vllm"].started == false &&
      output.ansible_inventory.containers["companion"].started == false
    )
    error_message = "Selecting Strata must run only its guest when all peer containers are configured stopped."
  }
}

run "strata_selector_rejects_another_running_container" {
  command = plan

  variables {
    llm_gpu_engine = "strata"
    containers = {
      llama = {
        hostname                = "llm-ada-lovelace-6-24GB-engine-a"
        vm_id                   = 610021
        node_name               = "compute-a"
        vlan                    = "ai"
        dhcp                    = true
        tags                    = ["gpu-passthrough"]
        llm_gpu_engine_identity = "llama_cpp"
      }
      vllm = {
        hostname                = "llm-ada-lovelace-6-24GB-engine-b"
        vm_id                   = 610022
        node_name               = "compute-a"
        vlan                    = "ai"
        dhcp                    = true
        tags                    = ["gpu-passthrough"]
        llm_gpu_engine_identity = "vllm"
      }
      strata = {
        hostname                = "llm-ada-lovelace-6-24GB-engine-c"
        vm_id                   = 610024
        node_name               = "compute-a"
        vlan                    = "ai"
        dhcp                    = true
        tags                    = ["gpu-passthrough"]
        llm_gpu_engine_identity = "strata"
      }
      companion = {
        hostname  = "example-companion"
        vm_id     = 610025
        node_name = "compute-a"
        vlan      = "ai"
        dhcp      = true
        started   = true
      }
      legacy = {
        hostname      = "llm-ada-lovelace-6-24GB-legacy"
        vm_id         = 610023
        node_name     = "compute-a"
        vlan          = "ai"
        dhcp          = true
        tags          = ["llm-gpu", "gpu-passthrough"]
        started       = true
        start_on_boot = true
      }
    }
  }

  expect_failures = [terraform_data.llm_gpu_strata_exclusive_guard]
}
