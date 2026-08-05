terraform {
  required_version = ">= 1.11"
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.111"
    }
    # Publishes ansible_inventory to homelab RustFS (inventory_publish.tf).
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.1"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

# Local variables for cloud-init files
locals {
  ansible_cloud_init = file(startswith(var.ansible_cloud_init_file, "/") ? var.ansible_cloud_init_file : "${path.module}/../../${var.ansible_cloud_init_file}")
}

# Storage module - manages datastores and storage configuration
module "storage" {
  source = "../storage"

  node_name   = var.proxmox_node
  datastores  = var.datastores
  environment = var.environment
}

# Pool module - manages resource pools
module "pools" {
  source = "../proxmox-pool"

  pools       = var.pools
  environment = var.environment
}

# VM module - creates and manages virtual machines
module "vms" {
  source = "../proxmox-vm"

  vms = {
    for k, v in var.vms : k => merge(v, {
      node_name      = v.node_name
      cdrom_file_id  = v.cdrom_file_id
      cdrom_file_ids = v.cdrom_file_ids
      tpm_state      = v.tpm_state
      efi_disk       = v.efi_disk
      clone_template = v.clone_template
      # DRY: IP/gateway derived from the VM's VLAN CIDR + vm_id (see locals.tf).
      ip_config = {
        ipv4_address = local.vm_ipv4[k]
        ipv4_gateway = local.vm_gateway[k]
      }
      # NIC onto the VM's service VLAN; DHCP-first VMs get a deterministic MAC
      # (local.vm_mac) so the lease survives a rebuild, same pattern as containers.
      network_interfaces = [
        for ni in v.network_interfaces : merge(ni, {
          vlan_id     = lookup(var.vlan_ids, v.vlan, null)
          mac_address = try(v.dhcp, false) ? local.vm_mac[k] : null
        })
      ]
      user_account = v.user_account != null ? {
        username = v.user_account.username
        password = v.user_account.password
        keys     = [trimspace(var.vm_ssh_public_key)]
      } : null
      # Override cloud-init for ansible VM to use external file
      cloud_init_user_data = k == "ansible" ? local.ansible_cloud_init : v.cloud_init_user_data
    })
  }

  environment       = var.environment
  default_datastore = var.datastore_default
  domain            = var.domain

  # SSH credentials for provisioners (BPG provider reads auth from PROXMOX_VE_* env vars)
  proxmox_ssh_username    = var.proxmox_ssh_username
  proxmox_ssh_private_key = var.proxmox_ssh_private_key

  depends_on = [module.pools]
}

# Container module - creates and manages containers (optional)
# DRY: IPs are derived from vm_id unless explicitly specified
module "containers" {
  count  = length(var.containers) > 0 ? 1 : 0
  source = "../proxmox-container"

  containers = {
    for k, v in var.containers : k => merge(v, {
      node_name        = v.node_name
      template_file_id = "${var.datastore_iso}:vztmpl/${var.proxmox_ct_template_debian}"
      # DRY: IP/gateway derived from the LXC's VLAN CIDR + vm_id (see locals.tf).
      # local.container_ipv4 already honors a per-container static ipv4_address override.
      ip_config = {
        ipv4_address = local.container_ipv4[k]
        ipv4_gateway = local.container_gateway[k]
      }
      # Tag every NIC onto the LXC's service VLAN (802.1Q id from var.vlan_ids).
      # DHCP-first guests also get a deterministic MAC (local.container_mac) so a
      # rebuilt guest renews the SAME lease and keeps its address and its name —
      # nothing reserves an address for it. Static guests keep a null MAC
      # (provider auto-generates) so they are not replaced.
      network_interfaces = [
        for ni in v.network_interfaces : merge(ni, {
          vlan_id     = lookup(var.vlan_ids, v.vlan, null)
          mac_address = try(v.dhcp, false) ? local.container_mac[k] : null
        })
      ]
      # DRY: Always inject SSH key for Ansible access
      # Uses container's password/keys if specified, otherwise empty password with SSH key only
      user_account = {
        password = try(v.user_account.password, "")
        keys = concat(
          try(v.user_account.keys, []),
          [trimspace(var.vm_ssh_public_key)]
        )
      }
    })
  }

  environment       = var.environment
  default_datastore = var.datastore_default
  domain            = var.domain

  depends_on = [module.pools, module.storage]
}

# Splunk VM module - Docker-based Splunk Enterprise
# DRY: IP is derived from vm_id using local.splunk_derived_ip
# SECURITY: VM is network-isolated (no internet access, RFC1918 only)
module "splunk_vm" {
  source = "../splunk-vm"

  vm_id          = var.splunk_vm_id
  name           = var.splunk_vm_name
  ip_address     = local.splunk_derived_ip # DRY: derived from splunk_vm_id
  gateway        = local.splunk_network_gateway
  node_name      = var.splunk_node_name
  cpu_type       = var.splunk_cpu_type
  migrate        = var.splunk_migrate
  pool_id        = var.splunk_vm_pool_id
  template_id    = var.template_id
  datastore_id   = var.datastore_id
  bridge         = var.bridge
  vlan_id        = lookup(var.vlan_ids, "siem", null) # tag the NIC onto siem; DRY with container pattern
  ssh_public_key = var.ssh_public_key != "" ? var.ssh_public_key : trimspace(var.vm_ssh_public_key)
  boot_disk_size = var.splunk_boot_disk_size
  data_disk_size = var.splunk_data_disk_size
  cpu_cores      = var.splunk_cpu_cores
  memory         = var.splunk_memory
  domain         = var.domain

  # Tiered storage: fast-splunk (hot/warm) and bulk-splunk (cold). datastore_ids
  # are the Proxmox zfspool storage ids that ansible-proxmox registers from the
  # matching node_storage datasets' pvesm_id. Both tiers carry backup = false —
  # index data is reconstructible and a block backup would roughly double the
  # storage consumed for no resilience gain; durability comes from the
  # Backblaze B2 frozen archive (configured Splunk-side), never from vzdump.
  tiered_disks = {
    fast = { datastore_id = "fast-splunk", interface = "virtio2", size = var.splunk_fast_disk_size, backup = false }
    bulk = { datastore_id = "bulk-splunk", interface = "virtio3", size = var.splunk_bulk_disk_size, backup = false }
  }

  depends_on = [module.pools]
}

# ACME Certificate module - Let's Encrypt via Route53
module "acme_certificates" {
  count  = length(var.acme_accounts) > 0 ? 1 : 0
  source = "../acme-certificate"

  acme_accounts     = var.acme_accounts
  dns_plugins       = var.dns_plugins
  acme_certificates = var.acme_certificates
  environment       = var.environment

  # SSH credentials for cert-delivery provisioner.
  proxmox_ssh_host        = var.proxmox_ssh_host
  proxmox_ssh_username    = var.proxmox_ssh_username
  proxmox_ssh_private_key = var.proxmox_ssh_private_key

  # Ensure the LXCs/VMs we deliver to exist before the cert lands.
  depends_on = [module.pools, module.containers, module.vms, module.splunk_vm]
}

# Rack-server cluster inventory (private RustFS values).
module "rack_server_cluster" {
  source       = "../rack-server-cluster"
  rack_servers = var.rack_servers
}

# The former null_resource.ansible_ssh_key_setup (copying the shared VM
# private key onto the ansible control guest) is retired: automation now
# authenticates with short-TTL certificates from the OpenBao SSH client CA
# (ssh-certificate-authority ADR), and the control guest is an LXC converged
# over pct. Verified absent on the live guest before removal.
