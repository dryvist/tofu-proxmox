variable "acme_iam_user_name" {
  description = "Name of the existing IAM user used by ACME DNS-01 clients (e.g. Traefik lego). Not created or destroyed by this module -- only added to the group this module manages."
  type        = string

  validation {
    condition     = can(regex("^acme-[a-z0-9-]+$", var.acme_iam_user_name))
    error_message = "acme_iam_user_name must start with 'acme-' to match the permissions-boundary scope on the deployer role that applies this module."
  }
}

variable "acme_iam_group_name" {
  description = "Name of the IAM group this module creates and uses to grant the scoped Route53 DNS-01 policy. The group is exclusive to this module -- its membership list is fully managed here."
  type        = string
  default     = "acme-dns01"

  validation {
    condition     = can(regex("^acme-[a-z0-9-]+$", var.acme_iam_group_name))
    error_message = "acme_iam_group_name must start with 'acme-' to match the permissions-boundary scope on the deployer role that applies this module."
  }
}

variable "route53_zone_ids" {
  description = "Route53 hosted zone IDs the ACME DNS-01 group may write _acme-challenge TXT records in (e.g. the parent zone and the ingress zone)."
  type        = list(string)

  validation {
    condition     = length(var.route53_zone_ids) > 0
    error_message = "At least one Route53 hosted zone ID is required."
  }

  validation {
    condition     = alltrue([for id in var.route53_zone_ids : can(regex("^Z[A-Z0-9]+$", id))])
    error_message = "Every Route53 zone ID must start with 'Z' followed by alphanumeric characters."
  }
}
