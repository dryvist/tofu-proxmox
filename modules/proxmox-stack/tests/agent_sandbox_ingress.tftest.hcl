# Tests for the agent-sandbox ingress split: ZCode Web stays on its own sandbox
# VM when a second agent-sandbox VM carries the "openhands" tag, and that VM
# gets the OpenHands browser UI + automation-events webhook routes. Also covers
# both sandbox VMs keeping the agent-sandbox firewall profile selection
# (ai_sandbox_vm_ids drives the firewall module's for_each).
# All runs use mocked providers and plan only.

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
    name       = "splunk-example"
    ip_address = "192.0.2.200"
    tiered_disks = {
      fast = { datastore_id = "fast-example", interface = "virtio2", size = 1024, backup = true }
      bulk = { datastore_id = "bulk-example", interface = "virtio3", size = 2048, backup = false }
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
  vm_ssh_public_key       = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHVTuJXKeZvvLsHLW0Fb4IPre13X8iheexMI8n3vT46+ fixture@example.test"
  proxmox_user            = "root"
  proxmox_ssh_private_key = "-----BEGIN FIXTURE PLACEHOLDER-----\nfixture-value-redacted\n-----END FIXTURE PLACEHOLDER-----"
  network_cidrs           = { for name, id in var.vlan_ids : name => "192.168.${id}.0/24" }
  domain                  = "example.test"
  nodes                   = { node-example = { role = "node-1" } }
}

run "single_sandbox_vm_keeps_zcode_route_and_publishes_no_openhands" {
  command = plan

  variables {
    vms = {
      "ai-sandbox-01" = {
        vm_id     = 515100
        node_name = "node-example"
        vlan      = "ai"
        dhcp      = true
        tags      = ["opentofu", "docker", "agent-sandbox"]
      }
    }
  }

  assert {
    condition     = one([for r in output.ansible_inventory.ingress : r if r.name == "zcode"]).owner == "ai-sandbox-01" && one([for r in output.ansible_inventory.ingress : r if r.name == "zcode"]).port == 443 && one([for r in output.ansible_inventory.ingress : r if r.name == "zcode"]).sso
    error_message = "the single agent-sandbox VM must own the SSO-gated ZCode Web route on its service port"
  }

  assert {
    condition     = length([for r in output.ansible_inventory.ingress : r if r.name == "openhands" || r.name == "openhands-events"]) == 0
    error_message = "no OpenHands routes may exist without a VM carrying the openhands tag"
  }

  assert {
    condition     = output.ansible_inventory.constants.service_ports.openhands_web == 443
    error_message = "the OpenHands service port constant must be published as 443"
  }
}

run "openhands_vm_splits_zcode_and_openhands_routes" {
  command = plan

  variables {
    vms = {
      "ai-sandbox-01" = {
        vm_id     = 515100
        node_name = "node-example"
        vlan      = "ai"
        dhcp      = true
        tags      = ["opentofu", "docker", "agent-sandbox"]
      }
      "openhands-01" = {
        vm_id     = 515110
        node_name = "node-example"
        vlan      = "ai"
        dhcp      = true
        tags      = ["opentofu", "docker", "agent-sandbox", "openhands"]
      }
    }
  }

  # Both sandbox VMs still receive the agent-sandbox firewall profile
  # (ai_sandbox_vm_ids is the firewall module's for_each input).
  assert {
    condition     = length(local.ai_sandbox_vm_ids) == 2 && contains(keys(local.ai_sandbox_vm_ids), "ai-sandbox-01") && contains(keys(local.ai_sandbox_vm_ids), "openhands-01")
    error_message = "both agent-sandbox VMs must keep the sandbox firewall profile selection"
  }

  assert {
    condition     = one([for r in output.ansible_inventory.ingress : r if r.name == "zcode"]).owner == "ai-sandbox-01" && one([for r in output.ansible_inventory.ingress : r if r.name == "zcode"]).ip == "ai-sandbox-515100.example.test"
    error_message = "ZCode Web must stay on the sandbox VM without the openhands tag"
  }

  assert {
    condition     = one([for r in output.ansible_inventory.ingress : r if r.name == "openhands"]).owner == "openhands-01" && one([for r in output.ansible_inventory.ingress : r if r.name == "openhands"]).port == 443 && one([for r in output.ansible_inventory.ingress : r if r.name == "openhands"]).sso == true
    error_message = "the openhands-tagged VM must own the SSO-gated OpenHands browser UI route"
  }

  assert {
    condition     = one([for r in output.ansible_inventory.ingress : r if r.name == "openhands-events"]).hostname == "openhands" && one([for r in output.ansible_inventory.ingress : r if r.name == "openhands-events"]).path_prefix == "/api/automation/v1/events/" && one([for r in output.ansible_inventory.ingress : r if r.name == "openhands-events"]).priority == 100 && one([for r in output.ansible_inventory.ingress : r if r.name == "openhands-events"]).sso == false
    error_message = "the events webhook must be one narrow ungated path on the openhands hostname"
  }

  assert {
    condition     = one([for r in output.ansible_inventory.ingress : r if r.name == "openhands-events"]).owner == "openhands-01" && one([for r in output.ansible_inventory.ingress : r if r.name == "openhands-events"]).ip == "openhands-515110.example.test"
    error_message = "the events webhook route must be owned by the openhands-tagged VM at its derived FQDN"
  }
}
