# Guest-specific firewall profiles are derived from the combined tags.
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
    vm_id      = 200
    name       = "vm-example"
    ip_address = "192.0.2.200"
    tiered_disks = {
      fast = { datastore_id = "store-example", interface = "virtio2", size = 16, backup = true }
      bulk = { datastore_id = "store-example", interface = "virtio3", size = 16, backup = false }
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

variables {
  vm_ssh_public_key       = "ssh-ed25519 TEST"
  proxmox_user            = "test-user"
  proxmox_ssh_private_key = "-----BEGIN OPENSSH PRIVATE KEY-----\ntest\n-----END OPENSSH PRIVATE KEY-----"
  network_cidrs           = { for name in keys(var.vlan_ids) : name => "192.0.2.0/24" }
}

# A guest with no platform tag trips the firewall module's check, which a root test
# cannot expect; modules/firewall/tests/specialist_eval_rules.tftest.hcl covers it.
run "specialist_eval_tag_map_preserves_the_platform_tag" {
  command = plan

  variables {
    containers = {
      "guest-sim" = {
        vm_id = 101, node_name = "node-example", vlan = "ai"
        tags  = ["terraform", "container", "ai-orchestration", "specialist-eval", "sim-eval"]
      }
      "guest-langflow" = {
        vm_id = 102, node_name = "node-example", vlan = "ai"
        tags  = ["terraform", "container", "ai-orchestration", "specialist-eval", "langflow-eval"]
      }
      "guest-dify" = {
        vm_id = 103, node_name = "node-example", vlan = "ai"
        tags  = ["terraform", "container", "ai-orchestration", "specialist-eval", "dify-eval"]
      }
      "guest-production" = {
        vm_id = 201, node_name = "node-example", vlan = "ai"
        tags  = ["terraform", "container", "ai-orchestration"]
      }
    }
  }

  assert {
    condition = (
      local.specialist_eval_container_ids["guest-sim"] == { vm_id = 101, platform_tag = "sim-eval" } &&
      local.specialist_eval_container_ids["guest-langflow"] == { vm_id = 102, platform_tag = "langflow-eval" } &&
      local.specialist_eval_container_ids["guest-dify"] == { vm_id = 103, platform_tag = "dify-eval" } &&
      length(local.specialist_eval_container_ids) == 3
    )
    error_message = "Only specialist-eval guests must enter the map, each keeping its one platform tag."
  }

  assert {
    condition = (
      local.ai_orchestration_container_ids["guest-production"] == 201 &&
      length(local.ai_orchestration_container_ids) == 1 &&
      !contains(keys(local.ai_orchestration_container_ids), "guest-sim") &&
      !contains(keys(local.ai_orchestration_container_ids), "guest-langflow") &&
      !contains(keys(local.ai_orchestration_container_ids), "guest-dify") &&
      !contains(keys(local.specialist_eval_container_ids), "guest-production")
    )
    error_message = "Specialist-eval tags must override broad AI rules while production AI membership stays independent."
  }
}

run "pepper_tag_selects_only_the_proxied_hermes_guest" {
  command = plan

  variables {
    containers = {
      "guest-pepper" = {
        vm_id = 240, node_name = "node-example", vlan = "ai"
        tags  = ["hermes-agent", "hermes-pepper", "chromium", "hindsight-client", "firecrawl-client"]
      }
      "guest-plain" = {
        vm_id = 241, node_name = "node-example", vlan = "ai"
        tags  = ["hermes-agent", "chromium", "hindsight-client", "firecrawl-client"]
      }
      "guest-other" = {
        vm_id = 242, node_name = "node-example", vlan = "ai"
      }
    }
  }

  assert {
    condition = (
      local.hermes_pepper_container_ids == { "guest-pepper" = 240 } &&
      local.hermes_agent_container_ids == { "guest-pepper" = 240, "guest-plain" = 241 }
    )
    error_message = "Only hermes-pepper selects proxied egress; both Hermes guests retain their shared service rules."
  }
}
