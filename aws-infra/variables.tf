# AWS Provider Configuration

variable "aws_region" {
  description = "AWS region for all AWS resources"
  type        = string
  default     = "us-east-1"

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]{1}$", var.aws_region))
    error_message = "AWS region must be a valid region identifier (e.g., us-east-1)."
  }
}

variable "openbao_aws_mount" {
  description = "OpenBao AWS secrets-engine mount used by Terrakube jobs"
  type        = string
  default     = "aws"
}

variable "openbao_aws_role" {
  description = "OpenBao AWS role that mints the least-privilege Route53 session"
  type        = string
  default     = "tf-proxmox"
}

variable "openbao_aws_ttl" {
  description = "Lifetime requested for the per-run AWS STS session"
  type        = string
  default     = "1h"
}

# Route53 Configuration

variable "enable_route53_dns" {
  description = "Enable Route53 DNS record management"
  type        = bool
  default     = true
}

variable "route53_zone_id" {
  description = "Route53 hosted zone ID for DNS record management"
  type        = string

  validation {
    condition     = can(regex("^Z[A-Z0-9]+$", var.route53_zone_id))
    error_message = "Route53 zone ID must start with 'Z' followed by alphanumeric characters."
  }
}

# Proxmox integration values are non-secret Terrakube workspace inputs.

variable "proxmox_domain" {
  description = "Fully qualified domain name for Proxmox VE UI (e.g., pve.example.com)"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)*$", var.proxmox_domain))
    error_message = "Proxmox domain must be a valid fully qualified domain name."
  }
}

variable "proxmox_ip_address" {
  description = "Legacy single IP address of a Proxmox VE host. Used only when proxmox_ip_addresses is empty."
  type        = string
  default     = ""

  validation {
    condition     = var.proxmox_ip_address == "" || can(cidrnetmask("${var.proxmox_ip_address}/32"))
    error_message = "Proxmox IP address must be a valid IPv4 address."
  }
}

variable "proxmox_ip_addresses" {
  description = "IP addresses of active Proxmox VE API endpoints for the shared Proxmox UI/API DNS record."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for ip in var.proxmox_ip_addresses : can(cidrnetmask("${ip}/32"))])
    error_message = "Every Proxmox IP address must be a valid IPv4 address."
  }
}

variable "publish_proxmox_public_a" {
  description = "Publish the pve apex A record (RFC1918 node IPs) in the PUBLIC Route53 zone. Default false: internal clients resolve pve.<domain> via Technitium, so publishing it here only leaks internal IPs."
  type        = bool
  default     = false
}

variable "dns_ttl" {
  description = "DNS TTL in seconds for the A record"
  type        = number
  default     = 300

  validation {
    condition     = var.dns_ttl >= 60 && var.dns_ttl <= 86400
    error_message = "DNS TTL must be between 60 seconds (1 minute) and 86400 seconds (24 hours)."
  }
}

# Service-alias CNAMEs at the public zone apex (name label -> target FQDN).
# Values are supplied as a typed Terrakube workspace input; no hostname literal
# is committed here.
variable "route53_cnames" {
  description = "Map of service-alias CNAME records: record label (relative to the zone) -> target FQDN"
  type        = map(string)
  default     = {}

  validation {
    condition = alltrue([
      for label, target in var.route53_cnames :
      can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", lower(label)))
      && can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)*\\.?$", lower(target)))
    ])
    error_message = "Every CNAME entry must be a single record label mapped to a valid FQDN (optional trailing dot)."
  }
}

# Host A records at the public zone apex (name label -> IPv4 address). Values
# come from a typed Terrakube workspace input — no
# hostname or IP literal is ever committed here. This is the terminal record a
# service_cnames entry (e.g. llm-large) resolves to, and the only DNS source
# both internal (Technitium-forwarded) and external resolvers agree on.
variable "route53_a_records" {
  description = "Map of host A records: record label (relative to the zone) -> IPv4 address"
  type        = map(string)
  default     = {}

  validation {
    condition = alltrue([
      for label, ip in var.route53_a_records :
      can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", lower(label))) && can(cidrnetmask("${ip}/32"))
    ])
    error_message = "Every A-record entry must be a single record label mapped to a valid IPv4 address."
  }
}

# ACME DNS-01 IAM policy (deployer-managed, off by default)

variable "enable_acme_iam" {
  description = "Enable management of the scoped ACME DNS-01 IAM group/policy. Off by default so merging this change does nothing until the bootstrap deployer role exists."
  type        = bool
  default     = false
}

variable "openbao_acme_iam_role" {
  description = "OpenBao AWS role that mints the tightly bounded ACME-IAM-deployer session, separate from openbao_aws_role"
  type        = string
  default     = "tf-acme-iam"
}

variable "acme_iam_user_name" {
  description = "Name of the existing IAM user used by ACME DNS-01 clients (e.g. Traefik lego). Required when enable_acme_iam is true; never created by this configuration."
  type        = string
  default     = ""

  validation {
    condition     = !var.enable_acme_iam || can(regex("^acme-[a-z0-9-]+$", var.acme_iam_user_name))
    error_message = "acme_iam_user_name must start with 'acme-' and be set when enable_acme_iam is true."
  }
}

variable "acme_iam_group_name" {
  description = "Name of the IAM group this module creates to carry the scoped ACME DNS-01 policy"
  type        = string
  default     = "acme-dns01"
}

variable "acme_route53_zone_ids" {
  description = "Route53 hosted zone IDs the ACME DNS-01 group may write _acme-challenge TXT records in (e.g. the parent zone and the ingress zone). Required when enable_acme_iam is true."
  type        = list(string)
  default     = []

  validation {
    condition     = !var.enable_acme_iam || length(var.acme_route53_zone_ids) > 0
    error_message = "acme_route53_zone_ids must contain at least one zone ID when enable_acme_iam is true."
  }
}

# General

variable "environment" {
  description = "Environment name for tagging and organization"
  type        = string
  default     = "homelab"
}
