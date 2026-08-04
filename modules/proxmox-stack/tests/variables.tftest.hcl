# Tests for variables.tf - input validation rules
#
# Uses expect_failures to verify validation blocks reject bad input.
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
# aws is only used by the S3 inventory publish (inventory_publish.tf);
# mock it so tests need no AWS credentials in CI or locally.
mock_provider "aws" {}
mock_provider "null" {}

# Override data sources and modules that require real provider connections
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
    ip_address  = "192.168.40.200"
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

override_module {
  target = module.acme_certificates
  outputs = {
    acme_accounts = {}
    dns_plugins   = {}
    certificates  = {}
  }
}

# Shared valid defaults for all runs
variables {
  vm_ssh_public_key       = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestKeyData test@test"
  proxmox_ssh_private_key = "-----BEGIN OPENSSH PRIVATE KEY-----\ntest\n-----END OPENSSH PRIVATE KEY-----"
  # vlan_ids uses its variable default (single source of truth); network_cidrs is
  # derived from it as 192.168.<vlan_id>.0/24 — no duplicated VLAN/CIDR list.
  network_cidrs = { for name, id in var.vlan_ids : name => "192.168.${id}.0/24" }
}

# --- Positive test: valid inputs pass ---

run "valid_inputs_pass" {
  command = plan
}

# --- Negative tests: invalid inputs rejected ---

run "invalid_network_cidrs_rejected" {
  command = plan

  variables {
    network_cidrs = {
      siem    = "not-a-cidr"
      compute = "192.168.10.0/24"
    }
  }

  expect_failures = [
    var.network_cidrs,
  ]
}

run "splunk_vm_id_out_of_range_rejected" {
  command = plan

  variables {
    splunk_vm_id = 99999
  }

  expect_failures = [
    var.splunk_vm_id,
  ]
}

run "vm_with_invalid_vga_type_rejected" {
  command = plan

  variables {
    vms = {
      test = {
        vm_id     = 100
        node_name = "proxmox-1"
        name      = "test-vm"
        vlan      = "apps"
        vga_type  = "invalid-vga"
      }
    }
  }

  expect_failures = [
    var.vms,
  ]
}

run "vm_with_id_below_minimum_rejected" {
  command = plan

  variables {
    vms = {
      test = {
        vm_id     = 1
        node_name = "proxmox-1"
        name      = "test-vm"
        vlan      = "apps"
      }
    }
  }

  expect_failures = [
    var.vms,
  ]
}

run "container_with_id_below_minimum_rejected" {
  command = plan

  variables {
    containers = {
      test = {
        vm_id     = 1
        node_name = "proxmox-1"
        hostname  = "test"
        vlan      = "apps"
      }
    }
  }

  expect_failures = [
    var.containers,
  ]
}

run "container_with_excessive_cpu_rejected" {
  command = plan

  variables {
    containers = {
      test = {
        vm_id     = 100
        node_name = "proxmox-1"
        hostname  = "test"
        vlan      = "apps"
        cpu_cores = 64
      }
    }
  }

  expect_failures = [
    var.containers,
  ]
}

run "container_with_memory_below_minimum_rejected" {
  command = plan

  variables {
    containers = {
      test = {
        vm_id            = 100
        node_name        = "proxmox-1"
        hostname         = "test"
        vlan             = "apps"
        memory_dedicated = 0
      }
    }
  }

  expect_failures = [
    var.containers,
  ]
}
run "template_id_out_of_range_rejected" {
  command = plan

  variables {
    template_id = 10000
  }

  expect_failures = [
    var.template_id,
  ]
}

run "empty_datastore_id_rejected" {
  command = plan

  variables {
    datastore_id = ""
  }

  expect_failures = [
    var.datastore_id,
  ]
}

run "empty_bridge_rejected" {
  command = plan

  variables {
    bridge = ""
  }

  expect_failures = [
    var.bridge,
  ]
}

run "invalid_ssh_public_key_prefix_rejected" {
  command = plan

  variables {
    ssh_public_key = "not-a-valid-key"
  }

  expect_failures = [
    var.ssh_public_key,
  ]
}

run "invalid_proxmox_ssh_private_key_rejected" {
  command = plan

  variables {
    proxmox_ssh_private_key = "relative/path/no-slash-or-tilde"
  }

  expect_failures = [
    var.proxmox_ssh_private_key,
  ]
}

run "vm_with_excessive_cpu_cores_rejected" {
  command = plan

  variables {
    vms = {
      test = {
        vm_id     = 100
        node_name = "proxmox-1"
        name      = "test-vm"
        vlan      = "apps"
        cpu_cores = 64
      }
    }
  }

  expect_failures = [
    var.vms,
  ]
}

run "vm_with_memory_above_maximum_rejected" {
  command = plan

  variables {
    vms = {
      test = {
        vm_id            = 100
        node_name        = "proxmox-1"
        name             = "test-vm"
        vlan             = "apps"
        memory_dedicated = 131072
      }
    }
  }

  expect_failures = [
    var.vms,
  ]
}

run "vm_ssh_public_key_invalid_content_rejected" {
  command = plan

  variables {
    vm_ssh_public_key = "/home/user/.ssh/id_ed25519.pub"
  }

  expect_failures = [
    var.vm_ssh_public_key,
  ]
}

run "ansible_cloud_init_file_wrong_directory_rejected" {
  command = plan

  variables {
    ansible_cloud_init_file = "config/wrong-dir.yml"
  }

  expect_failures = [
    var.ansible_cloud_init_file,
  ]
}

run "splunk_vm_name_too_long_rejected" {
  command = plan

  variables {
    splunk_vm_name = "this-splunk-vm-name-is-way-too-long-exceeding-63-character-limit"
  }

  expect_failures = [
    var.splunk_vm_name,
  ]
}

run "splunk_boot_disk_size_out_of_range_rejected" {
  command = plan

  variables {
    splunk_boot_disk_size = 1001
  }

  expect_failures = [
    var.splunk_boot_disk_size,
  ]
}

run "splunk_data_disk_size_out_of_range_rejected" {
  command = plan

  variables {
    splunk_data_disk_size = 1001
  }

  expect_failures = [
    var.splunk_data_disk_size,
  ]
}

run "splunk_cpu_cores_out_of_range_rejected" {
  command = plan

  variables {
    splunk_cpu_cores = 64
  }

  expect_failures = [
    var.splunk_cpu_cores,
  ]
}

run "splunk_memory_out_of_range_rejected" {
  command = plan

  variables {
    splunk_memory = 65537
  }

  expect_failures = [
    var.splunk_memory,
  ]
}

run "acme_account_invalid_email_rejected" {
  command = plan

  variables {
    acme_accounts = {
      test = {
        email     = "not-an-email"
        directory = "https://acme-v02.api.letsencrypt.org/directory"
        tos       = "https://letsencrypt.org/documents/LE-SA-v1.4-April-3-2024.pdf"
      }
    }
  }

  expect_failures = [
    var.acme_accounts,
  ]
}

run "acme_account_non_https_directory_rejected" {
  command = plan

  variables {
    acme_accounts = {
      test = {
        email     = "admin@example.com"
        directory = "http://insecure.acme.org/directory"
        tos       = "https://letsencrypt.org/documents/LE-SA-v1.4-April-3-2024.pdf"
      }
    }
  }

  expect_failures = [
    var.acme_accounts,
  ]
}

run "acme_certificates_invalid_destination_kind_rejected" {
  command = plan

  variables {
    acme_certificates = {
      bad = {
        node_name     = "proxmox-1"
        domain        = "proxmox-1.example.com"
        account_id    = "default"
        dns_plugin_id = "AWS"
        destinations = [{
          kind        = "container"
          target_id   = 175
          bundle_path = "/etc/ssl/private/x.pem"
        }]
      }
    }
  }

  expect_failures = [
    var.acme_certificates,
  ]
}

run "acme_certificates_vm_missing_target_ip_rejected" {
  command = plan

  variables {
    acme_certificates = {
      bad = {
        node_name     = "proxmox-1"
        domain        = "proxmox-1.example.com"
        account_id    = "default"
        dns_plugin_id = "AWS"
        destinations = [{
          kind        = "vm"
          target_id   = 200
          bundle_path = "/etc/ssl/private/x.pem"
        }]
      }
    }
  }

  expect_failures = [
    var.acme_certificates,
  ]
}

run "acme_certificates_missing_path_combo_rejected" {
  command = plan

  variables {
    acme_certificates = {
      bad = {
        node_name     = "proxmox-1"
        domain        = "proxmox-1.example.com"
        account_id    = "default"
        dns_plugin_id = "AWS"
        destinations = [{
          kind      = "lxc"
          target_id = 175
          # No bundle_path, no cert_path/key_path — must be rejected.
        }]
      }
    }
  }

  expect_failures = [
    var.acme_certificates,
  ]
}

# An ai-runner guest with a misspelled egress-profile tag would match no
# firewall profile map and come up unfirewalled — the validation must catch it.
run "ai_runner_with_unknown_profile_tag_rejected" {
  command = plan

  variables {
    containers = {
      agent-1 = {
        vm_id     = 500101
        node_name = "proxmox-1"
        hostname  = "agent-1"
        vlan      = "ai"
        dhcp      = true
        tags      = ["terraform", "container", "ai", "ai-runner", "ai-proxeed"]
      }
    }
  }

  expect_failures = [
    var.containers,
  ]
}

run "ai_runner_with_no_profile_tag_rejected" {
  command = plan

  variables {
    containers = {
      agent-1 = {
        vm_id     = 500101
        node_name = "proxmox-1"
        hostname  = "agent-1"
        vlan      = "ai"
        dhcp      = true
        tags      = ["terraform", "container", "ai", "ai-runner"]
      }
    }
  }

  expect_failures = [
    var.containers,
  ]
}

run "ai_runner_with_two_profile_tags_rejected" {
  command = plan

  variables {
    containers = {
      agent-1 = {
        vm_id     = 500101
        node_name = "proxmox-1"
        hostname  = "agent-1"
        vlan      = "ai"
        dhcp      = true
        tags      = ["terraform", "container", "ai", "ai-runner", "ai-proxied", "ai-full-net"]
      }
    }
  }

  expect_failures = [
    var.containers,
  ]
}

# Positive: the agent pool + its Squid chokepoint is accepted as-is.
run "agent_pool_with_squid_accepted" {
  command = plan

  variables {
    containers = {
      agent-1 = {
        vm_id     = 500101
        node_name = "proxmox-1"
        hostname  = "agent-1"
        vlan      = "ai"
        dhcp      = true
        tags      = ["terraform", "container", "ai", "ai-runner", "ai-proxied"]
      }
      agent-2 = {
        vm_id     = 500102
        node_name = "proxmox-1"
        hostname  = "agent-2"
        vlan      = "ai"
        dhcp      = true
        tags      = ["terraform", "container", "ai", "ai-runner", "ai-proxied"]
      }
      squid = {
        vm_id     = 500110
        node_name = "proxmox-1"
        hostname  = "squid"
        vlan      = "ai"
        dhcp      = true
        tags      = ["terraform", "container", "ai", "squid"]
      }
    }
  }

  assert {
    condition     = length(local.ai_proxied_container_ids) == 2
    error_message = "both ai-proxied guests must select the pooled-agent profile, got ${length(local.ai_proxied_container_ids)}"
  }

  assert {
    condition     = length(local.squid_proxy_container_ids) == 1
    error_message = "the squid-tagged guest must select the proxy profile, got ${length(local.squid_proxy_container_ids)}"
  }
}
