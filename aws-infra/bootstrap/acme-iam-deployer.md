# ACME IAM deployer bootstrap (one-time, human-gated)

This module (`aws-infra/modules/acme-iam`) is feature-flagged off
(`enable_acme_iam = false`). Merging it changes nothing. Before flipping the
flag on, a human with existing IAM admin access performs the steps below
once. None of this is scripted by this repo on purpose: creating an IAM role
and a permissions boundary is a privileged, infrequent action that belongs at
a human gate, not in an unattended apply.

## a. Permissions boundary

Create a customer-managed policy named `acme-iam-deployer-boundary`. A
permissions boundary caps what any role/user that has it attached can ever
do, even if its own policy is broader — it is the backstop if the role
policy in step (b) is ever widened by mistake.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowOnlyAcmeIamObjects",
      "Effect": "Allow",
      "Action": [
        "iam:GetUser",
        "iam:GetGroup",
        "iam:GetGroupPolicy",
        "iam:PutGroupPolicy",
        "iam:DeleteGroupPolicy",
        "iam:CreateGroup",
        "iam:DeleteGroup",
        "iam:AddUserToGroup",
        "iam:RemoveUserFromGroup",
        "iam:ListGroupsForUser"
      ],
      "Resource": [
        "arn:aws:iam::*:user/acme-*",
        "arn:aws:iam::*:group/acme-*"
      ]
    }
  ]
}
```

## b. Deployer role `tf-acme-iam`

Create an IAM role named `tf-acme-iam` with:

- **Trust policy**: whatever principal the existing `tf-proxmox` role trusts
  (OpenBao's AWS secrets engine, via the same account/provider). Copy that
  role's trust policy as the starting point.
- **Permissions boundary**: `acme-iam-deployer-boundary` from step (a).
- **Permission policy**: the same Allow statement as the boundary in step
  (a), scoped to exactly the resources this module's three Terraform
  resources touch (`aws_iam_group`, `aws_iam_group_policy`,
  `aws_iam_group_membership`), **plus** explicit denies closing off
  everything else IAM:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowOnlyAcmeIamObjects",
      "Effect": "Allow",
      "Action": [
        "iam:GetUser",
        "iam:GetGroup",
        "iam:GetGroupPolicy",
        "iam:PutGroupPolicy",
        "iam:DeleteGroupPolicy",
        "iam:CreateGroup",
        "iam:DeleteGroup",
        "iam:AddUserToGroup",
        "iam:RemoveUserFromGroup",
        "iam:ListGroupsForUser"
      ],
      "Resource": [
        "arn:aws:iam::*:user/acme-*",
        "arn:aws:iam::*:group/acme-*"
      ]
    },
    {
      "Sid": "DenyUserAndKeyCreation",
      "Effect": "Deny",
      "Action": [
        "iam:CreateUser",
        "iam:CreateAccessKey",
        "iam:DeleteAccessKey",
        "iam:UpdateAccessKey"
      ],
      "Resource": "*"
    },
    {
      "Sid": "DenyAnyRoleAction",
      "Effect": "Deny",
      "Action": [
        "iam:AttachRolePolicy",
        "iam:DetachRolePolicy",
        "iam:PutRolePolicy",
        "iam:DeleteRolePolicy",
        "iam:*"
      ],
      "Resource": "arn:aws:iam::*:role/*"
    },
    {
      "Sid": "DenySelfAndBoundaryTampering",
      "Effect": "Deny",
      "Action": [
        "iam:DeleteRole",
        "iam:UpdateAssumeRolePolicy",
        "iam:DeletePolicy",
        "iam:CreatePolicyVersion",
        "iam:DeletePolicyVersion",
        "iam:SetDefaultPolicyVersion"
      ],
      "Resource": [
        "arn:aws:iam::*:role/tf-acme-iam",
        "arn:aws:iam::*:policy/acme-iam-deployer-boundary"
      ]
    }
  ]
}
```

The `DenyAnyRoleAction` statement is deliberately broad (`iam:*` on
`role/*`): this deployer manages groups and group policies only, never
roles, so denying every IAM action on every role closes off privilege
escalation via role creation/assumption entirely.

## c. OpenBao wiring

1. Create an `assumed_role` entry for the new role, following the same
   pattern as the existing `tf-proxmox` entry:

   ```text
   bao write aws/roles/tf-acme-iam \
     role_arns=arn:aws:iam::<account-id>:role/tf-acme-iam \
     credential_type=assumed_role
   ```

2. Grant the Terrakube workload identity read access to the new role's STS
   path, mirroring whatever policy already grants it `aws/sts/tf-proxmox`:

   ```hcl
   path "aws/sts/tf-acme-iam" {
     capabilities = ["read", "update"]
   }
   ```

   (`update`, not just `read`: `aws-infra/main.tf` requests the session with
   a `ttl`, which OpenBao serves as a write-style STS request.)

## d. Set the import/adoption variables

This module never creates the ACME IAM user — it only adds it as a member of
a new, exclusively-managed group (`aws_iam_group_membership`), because
attaching a policy directly to a user fails the repo's checkov gate
(`CKV_AWS_40`).

1. Find the existing user name:

   ```bash
   aws iam list-users --query "Users[?starts_with(UserName, 'acme')].UserName"
   ```

2. Set the Terrakube workspace variables:
   - `acme_iam_user_name` = that user name
   - `acme_route53_zone_ids` = the parent zone ID and the ingress zone ID
     (find with `aws route53 list-hosted-zones-by-name`)
   - `enable_acme_iam` = `true`

3. After the first successful apply, confirm the ACME client (e.g. Traefik
   lego) still issues/renews certificates using the new group's permissions,
   then manually remove the IAM user's old, wider inline policy (if one
   exists) so only the scoped group grant remains:

   ```bash
   aws iam list-user-policies --user-name <user>
   aws iam delete-user-policy --user-name <user> --policy-name <old-policy-name>
   ```
