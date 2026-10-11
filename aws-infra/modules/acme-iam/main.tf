terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

# NOTE: AWS provider is configured in the parent module (aws-infra/main.tf),
# via a dedicated alias minting credentials from a tightly bounded OpenBao
# role. This module inherits that provider from its parent.

# A dedicated group, exclusive to this module, carries the policy. Attaching
# IAM policies directly to a user fails CKV_AWS_40 (IAM policies must only be
# attached to groups or roles) -- the group indirection is the real fix, not a
# scan suppression. The existing ACME user is never created or destroyed by
# this module; it is only added as a member of this group.
resource "aws_iam_group" "acme" {
  name = var.acme_iam_group_name
}

resource "aws_iam_group_policy" "acme" {
  name   = "${var.acme_iam_group_name}-route53-dns01"
  group  = aws_iam_group.acme.name
  policy = jsonencode(local.acme_dns01_policy)
}

# Adds the existing user to the group THIS module owns, without touching any
# other group memberships the user may already have.
resource "aws_iam_user_group_membership" "acme" {
  user   = var.acme_iam_user_name
  groups = [aws_iam_group.acme.name]
}
