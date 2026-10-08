# Desired-state object: the fetch, and the guards that reject a desired state
# which would produce a broken plan.
#
# A deployment.json in the root directory takes priority over the object-store
# copy. A checkout without one (every caller today) keeps the existing
# RustFS-fetch behaviour unchanged.
locals {
  deployment_file_path   = "${path.root}/${var.deployment_file}"
  deployment_file_exists = fileexists(local.deployment_file_path)
}

data "aws_s3_object" "deployment" {
  count = local.deployment_file_exists ? 0 : 1

  bucket = var.deployment_bucket
  key    = var.deployment_key
}

locals {
  deployment_body = (
    local.deployment_file_exists
    ? file(local.deployment_file_path)
    : data.aws_s3_object.deployment[0].body
  )

  # Published into the Ansible inventory as desired_state.etag (see
  # modules/proxmox-stack/variables-infrastructure.tf). The object's own ETag
  # on the RustFS path; a content hash on the local-file path, since there is
  # no ETag to report there.
  desired_state_etag = (
    local.deployment_file_exists
    ? filemd5(local.deployment_file_path)
    : data.aws_s3_object.deployment[0].etag
  )
}
