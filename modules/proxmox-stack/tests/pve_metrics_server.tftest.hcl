# Tests for pve-metrics-server.tf's Cribl target derivation.
#
# The Graphite target must be an HAProxy guest's own FQDN (TCP frontend),
# never a "*.pve" ingress vhost name (HTTP-only, no DNS record). Covers both
# the happy path (one haproxy-tagged container) and the empty estate (no
# haproxy-tagged container -> the resource plans nothing).
#
# command = plan is sufficient: the resource's inputs are all known at plan
# time (no computed provider attributes feed into `server`).

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

variables {
  network_cidrs           = { for name, id in var.vlan_ids : name => "192.168.${id}.0/24" }
  vm_ssh_public_key       = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestKeyData test@test"
  proxmox_user            = "root"
  proxmox_ssh_private_key = "-----BEGIN OPENSSH PRIVATE KEY-----\ntest\n-----END OPENSSH PRIVATE KEY-----"
  domain                  = "example.com"
}

run "cribl_pve_metrics_targets_the_haproxy_guest_fqdn" {
  command = plan

  variables {
    containers = {
      "haproxy" = {
        vm_id     = 421040
        node_name = "proxmox-1"
        dhcp      = true
        hostname  = "haproxy"
        vlan      = "siem"
        tags      = ["terraform", "haproxy", "container"]
      }
    }
  }

  assert {
    condition     = length(proxmox_metrics_server.cribl_pve_metrics) == 1
    error_message = "an estate with one haproxy-tagged container must plan exactly one metrics-server resource"
  }

  assert {
    condition     = proxmox_metrics_server.cribl_pve_metrics[0].server == "haproxy.example.com"
    error_message = "the metrics-server target must be the haproxy guest's own FQDN, got ${proxmox_metrics_server.cribl_pve_metrics[0].server}"
  }
}

run "cribl_pve_metrics_plans_nothing_without_haproxy" {
  command = plan

  variables {
    containers = {
      "mailpit" = {
        vm_id     = 185
        node_name = "proxmox-1"
        hostname  = "mailpit"
        vlan      = "apps"
        tags      = ["terraform", "notifications", "container"]
      }
    }
  }

  assert {
    condition     = length(proxmox_metrics_server.cribl_pve_metrics) == 0
    error_message = "an estate with no haproxy-tagged container must plan zero metrics-server resources"
  }
}
