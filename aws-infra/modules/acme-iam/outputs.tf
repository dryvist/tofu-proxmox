output "group_name" {
  description = "Name of the IAM group carrying the ACME DNS-01 policy"
  value       = aws_iam_group.acme.name
}

output "group_arn" {
  description = "ARN of the IAM group carrying the ACME DNS-01 policy"
  value       = aws_iam_group.acme.arn
}
