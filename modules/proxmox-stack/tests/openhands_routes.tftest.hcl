# Tests for the OpenHands route set and the ZCode Web route's sandbox-host
# selection: zcode stays on the agent-sandbox VM that does NOT carry the
# "openhands" tag, while the OpenHands VM gets its own SSO-gated UI route plus
# the narrow ungated automation-events webhook scoped to the vikunja VLAN.
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

# One agent-sandbox VM, no "openhands" tag: today's single-sandbox behaviour is
# unchanged — the zcode route exists, owned by that VM, and no OpenHands route
# is emitted.
run "zcode_route_survives_without_an_openhands_vm" {
  command = plan

  variables {
    containers = {}
    vms = {
      "zcode-sandbox" = {
        vm_id     = 515100
        node_name = "node-example"
        name      = "zcode-sandbox"
        vlan      = "ai"
        dhcp      = true
        tags      = ["opentofu", "docker", "agent-sandbox"]
      }
    }
  }

  assert {
    condition     = length(local.openhands_vm_ids) == 0 && keys(local.zcode_web_vm_ids) == ["zcode-sandbox"]
    error_message = "without an openhands tag, every agent-sandbox VM must remain a ZCode Web host candidate"
  }

  assert {
    condition = try(
      one([for r in output.ansible_inventory.ingress : r if r.name == "zcode"]).owner == "zcode-sandbox" &&
      one([for r in output.ansible_inventory.ingress : r if r.name == "zcode"]).ip == "zcode-sandbox.example.test",
      false
    )
    error_message = "the zcode route must stay owned by the single agent-sandbox VM at its derived FQDN"
  }

  assert {
    condition     = length([for r in output.ansible_inventory.ingress : r if r.name == "openhands" || r.name == "openhands-events"]) == 0
    error_message = "no OpenHands route may be emitted without an openhands-tagged VM"
  }
}

# Two agent-sandbox VMs, one also tagged "openhands": the zcode route stays on
# the VM without the tag, the OpenHands VM owns both of its routes, and both
# VMs keep the agent-sandbox firewall profile selection.
run "openhands_vm_gets_its_own_routes_and_zcode_stays_put" {
  command = plan

  variables {
    containers = {
      vikunja = {
        vm_id     = 130
        node_name = "node-example"
        vlan      = "apps"
        dhcp      = true
        tags      = ["terraform", "container", "vikunja"]
      }
    }
    vms = {
      "zcode-sandbox" = {
        vm_id     = 515100
        node_name = "node-example"
        name      = "zcode-sandbox"
        vlan      = "ai"
        dhcp      = true
        tags      = ["opentofu", "docker", "agent-sandbox"]
      }
      "openhands-vm" = {
        vm_id     = 515200
        node_name = "node-example"
        name      = "openhands"
        vlan      = "ai"
        dhcp      = true
        tags      = ["opentofu", "docker", "agent-sandbox", "openhands"]
      }
    }
  }

  assert {
    condition     = local.ai_sandbox_vm_ids == { "zcode-sandbox" = 515100, "openhands-vm" = 515200 }
    error_message = "both agent-sandbox VMs must keep the sandbox firewall profile selection"
  }

  assert {
    condition     = keys(local.openhands_vm_ids) == ["openhands-vm"] && keys(local.zcode_web_vm_ids) == ["zcode-sandbox"]
    error_message = "the openhands tag must split the sandbox set into the OpenHands host and the ZCode Web host"
  }

  assert {
    condition = try(
      one([for r in output.ansible_inventory.ingress : r if r.name == "zcode"]).owner == "zcode-sandbox" &&
      one([for r in output.ansible_inventory.ingress : r if r.name == "zcode"]).ip == "zcode-sandbox.example.test",
      false
    )
    error_message = "the zcode route must stay owned by the sandbox VM without the openhands tag"
  }

  assert {
    condition = try(
      one([for r in output.ansible_inventory.ingress : r if r.name == "openhands"]).owner == "openhands-vm" &&
      one([for r in output.ansible_inventory.ingress : r if r.name == "openhands"]).ip == "openhands.example.test" &&
      one([for r in output.ansible_inventory.ingress : r if r.name == "openhands"]).port == local.pipeline_constants.service_ports.openhands_web &&
      one([for r in output.ansible_inventory.ingress : r if r.name == "openhands"]).scheme == "http" &&
      one([for r in output.ansible_inventory.ingress : r if r.name == "openhands"]).sso,
      false
    )
    error_message = "the OpenHands browser UI route must be owned by the openhands VM on its service port behind SSO"
  }

  assert {
    condition = try(
      one([for r in output.ansible_inventory.ingress : r if r.name == "openhands-events"]).owner == "openhands-vm" &&
      one([for r in output.ansible_inventory.ingress : r if r.name == "openhands-events"]).hostname == "openhands" &&
      one([for r in output.ansible_inventory.ingress : r if r.name == "openhands-events"]).path_prefix == "/api/automation/v1/events/" &&
      one([for r in output.ansible_inventory.ingress : r if r.name == "openhands-events"]).priority == 100 &&
      one([for r in output.ansible_inventory.ingress : r if r.name == "openhands-events"]).sso == false,
      false
    )
    error_message = "the automation-events webhook must be one narrow ungated path on the shared openhands hostname"
  }

  assert {
    condition = try(
      one([for r in output.ansible_inventory.ingress : r if r.name == "openhands-events"]).source_ranges == ["192.168.${var.vlan_ids["apps"]}.0/24"],
      false
    )
    error_message = "the webhook route must carry the vikunja VLAN CIDR as its only source range"
  }

  assert {
    condition = try(
      one([for r in output.ansible_inventory.ingress : r if r.name == "openhands"]).source_ranges == null,
      true
    )
    error_message = "the browser UI route must carry no source ranges"
  }
}
