# Policy is built as a local jsonencode()'d map rather than an
# aws_iam_policy_document data source: the data source's `json` attribute is
# provider-computed, so it comes back unknown under mock_provider and can't be
# asserted on in a tofu test plan. A local map is evaluated by OpenTofu itself,
# so it is both provider-independent and directly testable.
locals {
  acme_zone_arns = formatlist("arn:aws:route53:::hostedzone/%s", var.route53_zone_ids)

  acme_dns01_policy = {
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ListZones"
        Effect   = "Allow"
        Action   = ["route53:ListHostedZonesByName", "route53:ListHostedZones"]
        Resource = "*"
      },
      {
        Sid      = "GetChangeStatus"
        Effect   = "Allow"
        Action   = ["route53:GetChange"]
        Resource = "arn:aws:route53:::change/*"
      },
      {
        Sid      = "ReadScopedZones"
        Effect   = "Allow"
        Action   = ["route53:GetHostedZone", "route53:ListResourceRecordSets"]
        Resource = local.acme_zone_arns
      },
      {
        Sid      = "WriteAcmeChallengeTxtOnly"
        Effect   = "Allow"
        Action   = ["route53:ChangeResourceRecordSets"]
        Resource = local.acme_zone_arns
        Condition = {
          "ForAllValues:StringEquals" = {
            "route53:ChangeResourceRecordSetsRecordTypes" = ["TXT"]
          }
          "ForAllValues:StringLike" = {
            "route53:ChangeResourceRecordSetsNormalizedRecordNames" = ["_acme-challenge.*"]
          }
        }
      }
    ]
  }
}
