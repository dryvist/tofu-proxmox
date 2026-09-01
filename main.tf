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
        # Static and derived (cidrhost over the cluster's own VLAN + peer
        # suffix), not dhcp + a reserved octet — see docs/DR_HA.md W6 for why.
        ip_config = {
          ipv4_address = format(
            "%s/%s",
            cidrhost(local.deployment.network_cidrs[local.openbao_cluster.vlan], peer.suffix),
            split("/", local.deployment.network_cidrs[local.openbao_cluster.vlan])[1],
          )
        }
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

module "homelab" {
  source = "./modules/proxmox-stack"

  acme_accounts           = try(local.deployment.acme_accounts, {})
  acme_certificates       = try(local.deployment.acme_certificates, {})
  ansible_cloud_init_file = "${path.root}/${try(local.deployment.ansible_cloud_init_file, "cloud-init/ansible-server-example.yml")}"
  bridge                  = try(local.deployment.bridge, "vmbr0")
  containers              = local.containers
  datastore_default       = try(local.deployment.datastore_default, "local-zfs")
  datastore_id            = try(local.deployment.datastore_id, "local-zfs")
  datastore_iso           = try(local.deployment.datastore_iso, "local")
  datastores              = try(local.deployment.datastores, {})
  dns_plugins             = try(local.deployment.dns_plugins, {})
  domain                  = local.deployment.domain
  environment             = try(local.deployment.environment, "homelab")
  # Install-media object prefix. Optional because most applies never touch a
  # template build; when the key is absent the module's placeholder default
  # fails at download time (unresolvable host) rather than fetching the wrong
  # file, and every object is sha256-pinned regardless.
  iso_base_url = try(local.deployment.iso_base_url, "https://s3.example.com/isos")
  # Heavy-tier LLM serving host: a tofu-unifi reservation rather than a PVE
  # guest, so it has no vm_id to derive an address from and must be described
  # explicitly. Optional (try/"") because most applies have nothing to do with
  # the LLM fabric; the consuming roles fail loudly when it is absent rather
  # than substituting a default. See modules/proxmox-stack/variables-serving.tf.
  llm_large_serving_host = try(local.deployment.llm_large_serving_host, "")
  llm_large_serving_ip   = try(local.deployment.llm_large_serving_ip, "")
  network_cidrs          = local.deployment.network_cidrs
  network_domains        = try(local.deployment.network_domains, {})
  node_storage           = try(local.deployment.node_storage, {})
  nodes                  = local.deployment.nodes
  # Degraded-window acknowledgement for the OpenBao voter-spread guard —
  # per-run via TF_VAR_openbao_accept_quorum_loss_on_node_failure, default off.
  openbao_accept_quorum_loss_on_node_failure = var.openbao_accept_quorum_loss_on_node_failure
  pools                                      = local.deployment.pools
  proxmox_ct_template_debian                 = try(local.deployment.proxmox_ct_template_debian, "debian-13-standard_13.1-2_amd64.tar.zst")
  nixos_ct_template_file_name                = try(local.deployment.nixos_ct_template_file_name, "nixos-herdr-lxc.tar.xz")
  nixos_ct_template_sha256                   = try(local.deployment.nixos_ct_template_sha256, "")
  nixos_ct_template_url                      = try(local.deployment.nixos_ct_template_url, "")
  proxmox_iso_debian                         = try(local.deployment.proxmox_iso_debian, "debian-13.2.0-amd64-netinst.iso")
  proxmox_node                               = local.deployment.proxmox_node
  proxmox_ssh_host                           = ephemeral.vault_kv_secret_v2.proxmox.data.PROXMOX_VE_HOSTNAME
  proxmox_ssh_private_key                    = ephemeral.vault_kv_secret_v2.proxmox.data.PROXMOX_SSH_PRIVATE_KEY
  proxmox_ssh_username                       = ephemeral.vault_kv_secret_v2.proxmox.data.PROXMOX_SSH_USERNAME

  rack_servers          = try(local.deployment.rack_servers, {})
  splunk_boot_disk_size = try(local.deployment.splunk_boot_disk_size, 25)
  splunk_bulk_disk_size = try(local.deployment.splunk_bulk_disk_size, 2048)
  splunk_cpu_cores      = try(local.deployment.splunk_cpu_cores, 8)
  splunk_data_disk_size = try(local.deployment.splunk_data_disk_size, 200)
  splunk_fast_disk_size = try(local.deployment.splunk_fast_disk_size, 1024)
  splunk_cpu_type       = try(local.deployment.splunk_cpu_type, "host")
  splunk_memory         = try(local.deployment.splunk_memory, 12288)
  splunk_migrate        = try(local.deployment.splunk_migrate, false)
  # Fallback rationale: modules/proxmox-stack/variables-splunk.tf.
  splunk_node_name  = try(local.deployment.splunk_node_name, local.deployment.proxmox_node)
  splunk_vm_id      = try(local.deployment.splunk_vm_id, 99)
  splunk_vm_name    = try(local.deployment.splunk_vm_name, "splunk-vm")
  splunk_vm_pool_id = try(local.deployment.splunk_vm_pool_id, "")
  ssh_public_key    = try(local.deployment.ssh_public_key, "")
  template_id       = try(local.deployment.template_id, 9201)
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
  vdi_preserved_vlans = try(local.deployment.vdi_preserved_vlans, [])
  vm_ssh_public_key   = local.deployment.vm_ssh_public_key
  vms                 = try(local.deployment.vms, {})

  inventory_bucket = var.inventory_bucket
  inventory_key    = var.inventory_key

  desired_state_etag = data.aws_s3_object.deployment.etag
}
