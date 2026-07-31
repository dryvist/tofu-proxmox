terraform {
  required_version = ">= 1.11"

  # organization and hostname are intentionally omitted: OpenTofu reads them
  # from TF_CLOUD_ORGANIZATION / TF_CLOUD_HOSTNAME so this file carries no
  # environment-specific value.
  cloud {
    workspaces {
    }
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.111"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "~> 5.10"
    }
  }
}

# Terrakube supplies a short-lived OpenBao token through its native workload
# identity integration. No AppRole secret or long-lived token is stored in the
# workspace.
provider "vault" {
  skip_child_token = true
}

ephemeral "vault_kv_secret_v2" "object_storage" {
  mount = var.openbao_kv_mount
  name  = var.openbao_object_storage_path
}

ephemeral "vault_kv_secret_v2" "proxmox" {
  mount = var.openbao_kv_mount
  name  = var.openbao_proxmox_path
}

provider "aws" {
  region                      = ephemeral.vault_kv_secret_v2.object_storage.data.S3_REGION
  access_key                  = ephemeral.vault_kv_secret_v2.object_storage.data.S3_ACCESS_KEY_ID
  secret_key                  = ephemeral.vault_kv_secret_v2.object_storage.data.S3_SECRET_ACCESS_KEY
  s3_use_path_style           = true
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_region_validation      = true
  skip_requesting_account_id  = true

  endpoints {
    s3 = ephemeral.vault_kv_secret_v2.object_storage.data.S3_ENDPOINT
  }
}

provider "proxmox" {
  endpoint  = ephemeral.vault_kv_secret_v2.proxmox.data.PROXMOX_VE_ENDPOINT
  api_token = ephemeral.vault_kv_secret_v2.proxmox.data.PROXMOX_VE_API_TOKEN
  insecure  = lower(ephemeral.vault_kv_secret_v2.proxmox.data.PROXMOX_VE_INSECURE) == "true"

  ssh {
    agent       = false
    username    = ephemeral.vault_kv_secret_v2.proxmox.data.PROXMOX_SSH_USERNAME
    private_key = ephemeral.vault_kv_secret_v2.proxmox.data.PROXMOX_SSH_PRIVATE_KEY
  }
}

data "aws_s3_object" "deployment" {
  bucket = var.deployment_bucket
  key    = var.deployment_key
}

locals {
  deployment = jsondecode(data.aws_s3_object.deployment.body)

  openbao_cluster         = try(local.deployment.openbao_cluster, {})
  openbao_cluster_enabled = try(local.openbao_cluster.enabled, false)
  openbao_cluster_peers = local.openbao_cluster_enabled ? flatten([
    for node_name, suffixes in local.openbao_cluster.placement : [
      for suffix in suffixes : {
        node_name = node_name
        suffix    = suffix
      }
    ]
  ]) : []
  openbao_generated_containers = local.openbao_cluster_enabled ? {
    for peer in local.openbao_cluster_peers :
    format("%s%02d", try(local.openbao_cluster.name_prefix, "openbao-"), peer.suffix) => merge(
      try(local.openbao_cluster.container_defaults, {}),
      {
        vm_id     = try(local.openbao_cluster.vm_id_base, 110000) + peer.suffix
        vlan      = local.openbao_cluster.vlan
        hostname  = format("%s%02d", try(local.openbao_cluster.name_prefix, "openbao-"), peer.suffix)
        node_name = peer.node_name
        # DHCP reservation, not a static address baked into the guest config.
        # Every other guest in this stack takes `dhcp = true` + `reserved_host`
        # (41 of them); this generator was still writing a literal `ip_config`
        # from cidrhost(), making its voters part of a five-guest legacy
        # exception rather than following the rule.
        #
        # `reserved_host` is the host octet UniFi pins the guest's deterministic
        # MAC to, and the DNS A record resolves to that same address. Keeping it
        # equal to the suffix preserves the addressing intent exactly — the voter
        # still lands on the same octet — while moving the authority for the
        # address out of the guest config and into the reservation, so the
        # reservation and the DNS record cannot disagree with what the guest
        # actually holds.
        dhcp          = true
        reserved_host = peer.suffix
        root_disk = {
          size         = tonumber(local.openbao_cluster.root_disk.size)
          datastore_id = try(local.openbao_cluster.root_disk_datastore_by_node[peer.node_name], try(local.openbao_cluster.root_disk.datastore_id, null))
        }
      }
    )
  } : {}

  containers = merge(
    try(local.deployment.containers, {}),
    local.openbao_generated_containers,
    local.node_service_containers,
  )
}

check "deployment_contract" {
  assert {
    condition = (
      try(length(local.deployment.containers), 0) > 0 &&
      try(length(local.deployment.nodes), 0) > 0 &&
      try(length(local.deployment.pools), 0) > 0 &&
      try(local.deployment.proxmox_node, "") != "" &&
      try(local.deployment.domain, "") != "" &&
      try(length(local.deployment.network_cidrs), 0) > 0 &&
      try(local.deployment.vm_ssh_public_key, "") != ""
    )
    error_message = "The RustFS deployment object must contain non-empty containers, nodes, pools, proxmox_node, domain, network_cidrs, and vm_ssh_public_key before a plan can run."
  }
}

module "homelab" {
  source = "./modules/proxmox-stack"

  acme_accounts              = try(local.deployment.acme_accounts, {})
  acme_certificates          = try(local.deployment.acme_certificates, {})
  ansible_cloud_init_file    = "${path.root}/${try(local.deployment.ansible_cloud_init_file, "cloud-init/ansible-server-example.yml")}"
  bridge                     = try(local.deployment.bridge, "vmbr0")
  containers                 = local.containers
  datastore_default          = try(local.deployment.datastore_default, "local-zfs")
  datastore_id               = try(local.deployment.datastore_id, "local-zfs")
  datastore_iso              = try(local.deployment.datastore_iso, "local")
  datastores                 = try(local.deployment.datastores, {})
  dns_plugins                = try(local.deployment.dns_plugins, {})
  domain                     = local.deployment.domain
  environment                = try(local.deployment.environment, "homelab")
  host_services              = try(local.deployment.host_services, {})
  network_cidrs              = local.deployment.network_cidrs
  node_storage               = try(local.deployment.node_storage, {})
  nodes                      = local.deployment.nodes
  pools                      = local.deployment.pools
  proxmox_ct_template_debian = try(local.deployment.proxmox_ct_template_debian, "debian-13-standard_13.1-2_amd64.tar.zst")
  proxmox_iso_debian         = try(local.deployment.proxmox_iso_debian, "debian-13.2.0-amd64-netinst.iso")
  proxmox_node               = local.deployment.proxmox_node
  proxmox_ssh_host           = ephemeral.vault_kv_secret_v2.proxmox.data.PROXMOX_VE_HOSTNAME
  proxmox_ssh_private_key    = ephemeral.vault_kv_secret_v2.proxmox.data.PROXMOX_SSH_PRIVATE_KEY
  proxmox_ssh_username       = ephemeral.vault_kv_secret_v2.proxmox.data.PROXMOX_SSH_USERNAME
  rack_servers               = try(local.deployment.rack_servers, {})
  splunk_boot_disk_size      = try(local.deployment.splunk_boot_disk_size, 25)
  splunk_bulk_disk_size      = try(local.deployment.splunk_bulk_disk_size, 2048)
  splunk_cpu_cores           = try(local.deployment.splunk_cpu_cores, 8)
  splunk_data_disk_size      = try(local.deployment.splunk_data_disk_size, 200)
  splunk_fast_disk_size      = try(local.deployment.splunk_fast_disk_size, 1024)
  splunk_memory              = try(local.deployment.splunk_memory, 12288)
  splunk_vm_id               = try(local.deployment.splunk_vm_id, 99)
  splunk_vm_name             = try(local.deployment.splunk_vm_name, "splunk-vm")
  splunk_vm_pool_id          = try(local.deployment.splunk_vm_pool_id, "")
  ssh_public_key             = try(local.deployment.ssh_public_key, "")
  template_id                = try(local.deployment.template_id, 9201)
  vlan_ids = try(local.deployment.vlan_ids, {
    lan_main  = 1
    dns       = 2
    mgmt      = 5
    bmc       = 8
    compute   = 10
    pipeline  = 25
    data      = 30
    siem      = 40
    ai        = 50
    apps      = 60
    media_svc = 70
    homeauto  = 80
    nonprod   = 90
  })
  vm_ssh_public_key = local.deployment.vm_ssh_public_key
  vms               = try(local.deployment.vms, {})

  inventory_bucket = var.inventory_bucket
  inventory_key    = var.inventory_key
}
