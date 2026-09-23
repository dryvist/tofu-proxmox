# Tests for splunk VM protection guarantees
#
# Verifies that the splunk VM module:
#   1. Plans successfully without splunk credentials (moved to Ansible/OpenBao)
#   2. Produces the expected outputs used by downstream Ansible repos
#   3. Handles non-default splunk_vm_id correctly in derived IPs (siem VLAN)

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

variables {
  vm_ssh_public_key       = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestKeyData test@test"
  proxmox_user            = "root"
  proxmox_ssh_private_key = "-----BEGIN OPENSSH PRIVATE KEY-----\ntest\n-----END OPENSSH PRIVATE KEY-----"
  # vlan_ids uses its variable default (single source of truth); network_cidrs is
  # derived from it as 192.168.<vlan_id>.0/24 — no duplicated VLAN/CIDR list.
  network_cidrs = { for name, id in var.vlan_ids : name => "192.168.${id}.0/24" }
}

# --- Test: no Splunk credentials required at Terraform level ---
# splunk_password and splunk_hec_token are consumed by Ansible directly from
# OpenBao. Terraform no longer needs them. This run verifies the plan succeeds
# without any credential variables.

run "plan_succeeds_without_splunk_credentials" {
  command = plan
}

# --- Test: ansible_inventory output contains splunk_vm at root level ---
# Downstream Ansible repos load this output and access tofu_data.splunk_vm.
# Any nesting change here breaks ansible-splunk inventory loading.

run "ansible_inventory_splunk_vm_at_root" {
  command = plan

  assert {
    condition     = output.ansible_inventory.splunk_vm != null
    error_message = "ansible_inventory must contain splunk_vm at root level (not nested under another key)"
  }
}

# --- Test: splunk IP is derived from vm_id on the siem VLAN, not hardcoded ---
# Changing splunk_vm_id must produce a different IP and be reflected in
# ansible_inventory. This prevents silent misconfiguration if the VM is
# renumbered.

run "splunk_ip_derived_from_vm_id" {
  command = plan

  variables {
    splunk_vm_id = 205
  }

  assert {
    condition     = local.splunk_derived_ip == "192.168.40.205/24"
    error_message = "splunk_derived_ip must track splunk_vm_id (205) on the siem VLAN, got ${local.splunk_derived_ip}"
  }
}
