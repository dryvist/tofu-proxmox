terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.113"
    }
  }
}

# Reference existing storage pools as data sources for validation
# These are created at the Proxmox/ZFS level and managed outside Terraform
# Data sources provide type safety and ensure storage exists before use

data "proxmox_datastores" "available" {
  node_name = var.node_name
}

# Datastore validation is handled by the BPG provider at resource creation time.
# If a referenced datastore doesn't exist, the provider returns a clear error.
# Previous check blocks were removed because the BPG provider doesn't mark
# the datastores attribute as computed, making them incompatible with tofu test.

# Common datastores in our environment:
#   - local       (dir, /var/lib/vz)          - ISOs, templates, backups
#   - local-zfs   (zfspool, rpool/data)       - VM disks, container rootfs
#   - ssd-pool    (zfspool, ssd-pool)         - High-performance VM disks

# TODO: Re-enable this resource once the datastore issues are resolved.
# This is currently disabled to allow for the initial deployment of the environment.
# Cloud-init configuration file for VMs
resource "proxmox_virtual_environment_file" "cloud_init_config" {
  count = var.enable_cloud_init_config ? 1 : 0

  content_type = "snippets"
  datastore_id = "local"
  node_name    = var.node_name

  source_raw {
    data = yamlencode({
      "#cloud-config" = true
      package_update  = true
      package_upgrade = true
      packages = [
        "qemu-guest-agent",
        "cloud-init",
        "curl",
        "wget"
      ]
      write_files = [
        {
          path    = "/etc/environment"
          content = "ENVIRONMENT=${var.environment}\n"
          append  = true
        }
      ]
      runcmd = [
        "systemctl enable qemu-guest-agent",
        "systemctl start qemu-guest-agent"
      ]
    })
    file_name = "${var.environment}-cloud-init.yml"
  }
}
