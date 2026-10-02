# Verifies the ACME DNS-01 group policy is scoped exactly as intended:
# TXT-only, _acme-challenge.*-only, no wildcard ChangeResourceRecordSets.
# The policy is a local jsonencode()'d map (see locals.tf), so it is fully
# evaluated by OpenTofu itself and testable under mock_provider -- an
# aws_iam_policy_document data source would come back as unknown computed
# JSON under a mock provider and couldn't be asserted on here.

mock_provider "aws" {}

variables {
  acme_iam_user_name  = "acme-traefik-dns01"
  acme_iam_group_name = "acme-dns01"
  route53_zone_ids    = ["Z1EXAMPLEPARENT", "Z2EXAMPLEINGRESS"]
}

run "scoped_policy_shape" {
  command = plan

  assert {
    condition     = can(jsondecode(aws_iam_group_policy.acme.policy))
    error_message = "group policy must be valid JSON"
  }

  assert {
    condition = (
      jsondecode(aws_iam_group_policy.acme.policy).Statement[3].Condition["ForAllValues:StringEquals"]["route53:ChangeResourceRecordSetsRecordTypes"]
      == ["TXT"]
    )
    error_message = "ChangeResourceRecordSets must be restricted to TXT records only"
  }

  assert {
    condition = (
      jsondecode(aws_iam_group_policy.acme.policy).Statement[3].Condition["ForAllValues:StringLike"]["route53:ChangeResourceRecordSetsNormalizedRecordNames"]
      == ["_acme-challenge.*"]
    )
    error_message = "ChangeResourceRecordSets must be restricted to _acme-challenge.* record names only"
  }

  assert {
    condition = (
      jsondecode(aws_iam_group_policy.acme.policy).Statement[3].Resource == [
        "arn:aws:route53:::hostedzone/Z1EXAMPLEPARENT",
        "arn:aws:route53:::hostedzone/Z2EXAMPLEINGRESS",
      ]
    )
    error_message = "ChangeResourceRecordSets resource must be scoped to the given zone ARNs, never a wildcard"
  }

  assert {
    condition     = !contains(jsondecode(aws_iam_group_policy.acme.policy).Statement[3].Resource, "*")
    error_message = "ChangeResourceRecordSets must never allow a wildcard resource"
  }

  assert {
    condition     = aws_iam_group_membership.acme.users == toset(["acme-traefik-dns01"])
    error_message = "group membership must contain exactly the configured ACME user"
  }
}

run "rejects_non_acme_prefixed_user" {
  command = plan

  variables {
    acme_iam_user_name = "traefik"
  }

  expect_failures = [var.acme_iam_user_name]
}

run "rejects_empty_zone_list" {
  command = plan

  variables {
    route53_zone_ids = []
  }

  expect_failures = [var.route53_zone_ids]
}
