# Does the root still fall back to the RustFS object when no local
# deployment.json exists? (Vikunja 3492 — see deployment_source.tf.) This is
# the state a normal checkout is always in — deployment.json is gitignored —
# so every ordinary contributor's plan takes this path, and it is the one
# covered by a real, automated `tofu test` here.
#
# Scoped to the two objects this file actually tests (data.aws_s3_object.
# deployment, output.deployment_validated) via plan_options.target. Without
# that, a plan of the WHOLE root also has to satisfy imports.tf's six
# unconditional `import` blocks (they name real container keys — see
# imports.tf) and module.homelab's ~40 arguments and its own internal
# `network_cidrs` lookups, none of which this file is about. Targeting works
# cleanly here because `data.aws_s3_object.deployment` has a real instance
# (count = 1) on this branch — see the local-file sibling's header for why
# the same approach does not carry over to the file-present branch, where
# that data source has count = 0.

mock_provider "aws" {}

run "file_absent_falls_back_to_s3" {
  command = plan

  plan_options {
    target = [
      data.aws_s3_object.deployment,
      output.deployment_validated,
    ]
  }

  # override_data's `values` block accepts no function calls (confirmed:
  # OpenTofu rejects `file()`/`jsonencode()` here at parse time), so this is
  # a literal, not a read of tests/fixtures/deployment.json.example — same
  # content by hand, same domain value scripts/tofu-test-root.sh's local-file
  # check uses, so a divergence between the two would be visible rather than
  # silently masked by two different fixture bodies both happening to pass.
  override_data {
    target = data.aws_s3_object.deployment
    values = {
      body = <<-JSON
        {
          "containers": {"c1": {"vm_id": 100, "hostname": "c1", "vlan": "lan_main", "node_name": "n1"}},
          "nodes": {"n1": {"role": "node-1", "cluster_roles": ["storage"]}},
          "pools": {"p1": {}},
          "proxmox_node": "n1",
          "proxmox_user": "terraform@pve",
          "domain": "file-source.example",
          "network_cidrs": {"lan_main": "10.0.0.0/24"},
          "vm_ssh_public_key": "ssh-ed25519 AAAAtest fixture"
        }
      JSON
      etag = "mock-etag-value"
    }
  }

  assert {
    condition     = length(data.aws_s3_object.deployment) == 1
    error_message = "without a local deployment.json, the RustFS data source must still be planned (count must be 1)."
  }

  # Same fixture content as the local-file test's sibling scenario: proves
  # the S3 body reaches local.deployment through the SAME output-precondition
  # path, not a second, divergent copy of the checks.
  assert {
    condition     = local.deployment.domain == "file-source.example"
    error_message = "the RustFS object's body should have reached local.deployment through the shared precondition path."
  }

  assert {
    condition     = local.desired_state_etag == "mock-etag-value"
    error_message = "desired_state_etag should be the RustFS object's own ETag on this path, not a content hash."
  }
}
