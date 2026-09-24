# Does the root still fall back to the RustFS object when no local
# deployment.json exists? Every ordinary checkout is in this state, since
# deployment.json is gitignored here.
#
# Scoped to the two objects this file tests via plan_options.target, else a
# plan of the whole root also has to satisfy imports.tf's unconditional
# `import` blocks and module.homelab's own arguments, unrelated to this file.

mock_provider "aws" {}

run "file_absent_falls_back_to_s3" {
  command = plan

  plan_options {
    target = [
      data.aws_s3_object.deployment,
      output.deployment_validated,
    ]
  }

  # override_data's `values` block accepts no function calls, so this is a
  # literal, not a read of tests/fixtures/deployment.json.example.
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

  assert {
    condition     = local.deployment.domain == "file-source.example"
    error_message = "the RustFS object's body should have reached local.deployment through the shared precondition path."
  }

  assert {
    condition     = local.desired_state_etag == "mock-etag-value"
    error_message = "desired_state_etag should be the RustFS object's own ETag on this path, not a content hash."
  }
}
