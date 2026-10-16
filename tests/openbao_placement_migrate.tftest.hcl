# A per-peer migration flag reaches the generated container while the default
# remains false for ordinal placement entries.
mock_provider "aws" {}

run "per_peer_migration_is_opt_in" {
  command = plan

  plan_options {
    target = [
      data.aws_s3_object.deployment,
      output.deployment_validated,
    ]
  }

  override_data {
    target = data.aws_s3_object.deployment
    values = {
      body = <<-JSON
        {
          "containers": {"c1": {"vm_id": 100, "hostname": "c1", "vlan": "lan_main", "node_name": "n1"}},
          "nodes": {
            "n1": {"role": "node-1", "cluster_roles": ["storage"]}, "n2": {"role": "node-2"},
            "n3": {"role": "node-3"}, "n4": {"role": "node-4"},
            "n5": {"role": "node-5"}
          },
          "pools": {"p1": {}},
          "proxmox_node": "n1",
          "proxmox_user": "root",
          "domain": "placement.example",
          "network_cidrs": {"lan_main": "10.0.0.0/24", "mgmt": "10.0.10.0/24"},
          "vm_ssh_public_key": "ssh-ed25519 AAAAtest fixture",
          "openbao_cluster": {
            "enabled": true,
            "name_prefix": "openbao-",
            "vm_id_base": 110000,
            "vlan": "mgmt",
            "placement": {
              "n1": [10],
              "n2": [{"vm_id": 110020, "hostname": "openbao-20", "migrate": true}],
              "n3": [30], "n4": [40], "n5": [50]
            },
            "container_defaults": {"tags": ["openbao"], "pool_id": "p1", "unprivileged": true},
            "root_disk": {"size": 8}
          }
        }
      JSON
      etag = "mock-openbao-migrate-etag"
    }
  }

  assert {
    condition     = local.openbao_generated_containers["openbao-20"].migrate && local.openbao_generated_containers["openbao-20"].node_name == "n2" && local.openbao_generated_containers["openbao-20"].vm_id == 110020
    error_message = "The object-form peer must retain its identity and node while passing migrate=true."
  }

  assert {
    condition     = local.openbao_generated_containers["openbao-10"].migrate == false
    error_message = "An integer placement item must keep migration disabled by default."
  }
}
