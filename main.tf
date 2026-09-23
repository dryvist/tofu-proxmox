terraform {
  required_version = ">= 1.11"

  # organization and hostname are intentionally omitted: OpenTofu reads them
  # from TF_CLOUD_ORGANIZATION / TF_CLOUD_HOSTNAME so this file carries no
  # environment-specific value.
  cloud {
    workspaces {
    }
  }

  # This repeats modules/proxmox-root's own required_providers. It cannot be
  # inherited: imports.tf's `import` blocks are root-only, and OpenTofu
  # resolves an import's provider from the ROOT module's own declarations,
  # not the nested module's — omitting this makes every proxmox-typed import
  # fail init with "hashicorp/proxmox does not exist" (it guesses the wrong
  # registry namespace from the resource type prefix alone).
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.113"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "~> 5.10"
    }
  }
}

# The reusable composition (providers, ephemeral credential fetches, the
# deployment-object decode, and the module.homelab call) lives in
# modules/proxmox-root, one directory down, so it can be sourced by another
# repository's own root module (Vikunja 3492 — a git-tracked desired-state
# repo). OpenTofu permits a `cloud` block and `import` blocks (../imports.tf)
# only in the true root module, so those two stay here rather than moving
# with the rest. Every existing infrastructure address is preserved by the
# `moved` block in migrations.tf.
module "stack" {
  source = "./modules/proxmox-root"

  openbao_kv_mount             = var.openbao_kv_mount
  openbao_object_storage_path  = var.openbao_object_storage_path
  openbao_proxmox_path         = var.openbao_proxmox_path
  deployment_bucket            = var.deployment_bucket
  deployment_key               = var.deployment_key
  deployment_json              = var.deployment_json
  ssh_ca_trust_rollout_enabled = var.ssh_ca_trust_rollout_enabled
  # Degraded-window acknowledgement for the OpenBao voter-spread guard —
  # per-run via TF_VAR_openbao_accept_quorum_loss_on_node_failure, default off.
  openbao_accept_quorum_loss_on_node_failure = var.openbao_accept_quorum_loss_on_node_failure
  inventory_bucket                           = var.inventory_bucket
  inventory_key                              = var.inventory_key
}
