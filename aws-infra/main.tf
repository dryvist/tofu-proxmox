terraform {
  required_version = ">= 1.10"

  # organization and hostname are intentionally omitted: OpenTofu reads them
  # from TF_CLOUD_ORGANIZATION / TF_CLOUD_HOSTNAME so this file carries no
  # environment-specific value.
  cloud {
    workspaces {
      name = "tofu-proxmox-aws-infra"
    }
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    vault = {
      source = "hashicorp/vault"
    }
  }
}

# Terrakube exchanges its per-run workload identity for VAULT_TOKEN. OpenBao's
# AWS secrets engine then mints a short-lived STS session. The ephemeral block
# guarantees that the credentials are not persisted in a plan or state.
provider "vault" {
  skip_child_token = true
}

ephemeral "vault_aws_access_credentials" "route53" {
  mount  = var.openbao_aws_mount
  role   = var.openbao_aws_role
  type   = "sts"
  region = var.aws_region
  ttl    = var.openbao_aws_ttl
}

provider "aws" {
  region     = var.aws_region
  access_key = ephemeral.vault_aws_access_credentials.route53.access_key
  secret_key = ephemeral.vault_aws_access_credentials.route53.secret_key
  token      = ephemeral.vault_aws_access_credentials.route53.security_token
}

# Second, separately scoped STS session for the ACME IAM deployer. Minted
# only when enable_acme_iam is true, from a role with permissions limited to
# managing the acme-* group/policy -- never the Route53 records role above.
ephemeral "vault_aws_access_credentials" "acme_iam" {
  count  = var.enable_acme_iam ? 1 : 0
  mount  = var.openbao_aws_mount
  role   = var.openbao_acme_iam_role
  type   = "sts"
  region = var.aws_region
  ttl    = var.openbao_aws_ttl
}

provider "aws" {
  alias      = "acme_iam"
  region     = var.aws_region
  access_key = one(ephemeral.vault_aws_access_credentials.acme_iam[*].access_key)
  secret_key = one(ephemeral.vault_aws_access_credentials.acme_iam[*].secret_key)
  token      = one(ephemeral.vault_aws_access_credentials.acme_iam[*].security_token)
}

# Route53 DNS Records module - manages A record for Proxmox VE UI
module "route53_records" {
  count  = var.enable_route53_dns ? 1 : 0
  source = "./modules/route53-records"

  route53_zone_id          = var.route53_zone_id
  proxmox_domain           = var.proxmox_domain
  proxmox_ip_address       = var.proxmox_ip_address
  proxmox_ip_addresses     = var.proxmox_ip_addresses
  route53_cnames           = var.route53_cnames
  route53_a_records        = var.route53_a_records
  publish_proxmox_public_a = var.publish_proxmox_public_a
  dns_ttl                  = var.dns_ttl
  environment              = var.environment
}

# ACME DNS-01 IAM policy - manages ONLY the scoped group/policy used by the
# existing ACME user (e.g. Traefik lego). Off by default: merging this change
# does nothing until the bootstrap deployer role exists (see
# aws-infra/bootstrap/acme-iam-deployer.md) and enable_acme_iam is flipped on.
module "acme_iam" {
  count  = var.enable_acme_iam ? 1 : 0
  source = "./modules/acme-iam"
  providers = {
    aws = aws.acme_iam
  }

  acme_iam_user_name  = var.acme_iam_user_name
  acme_iam_group_name = var.acme_iam_group_name
  route53_zone_ids    = var.acme_route53_zone_ids
}

# Future AWS resources go here:
# - S3 buckets for backups
# - CloudWatch alarms
# - etc.
