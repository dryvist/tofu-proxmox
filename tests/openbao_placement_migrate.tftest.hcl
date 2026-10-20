# Peer migration overrides the default; replica targets reach the generated
# container for target-aware migration resolution.
mock_provider "aws" {}

run "generated_peer_migration_preserves_explicit_values_and_target" {
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
          "network_cidrs": {"lan_main": "192.0.2.0/24", "mgmt": "198.51.100.0/24"},
          "vm_ssh_public_key": "ssh-ed25519 AAAAtest fixture",
          "openbao_cluster": {
            "enabled": true,
            "name_prefix": "openbao-",
            "vm_id_base": 110000,
            "vlan": "mgmt",
            "placement": {
              "n1": [10],
              "n3": [{"vm_id": 110020, "hostname": "openbao-20", "migrate": true}, 30],
              "n4": [40], "n5": [50]
            },
            "container_defaults": {"tags": ["openbao"], "pool_id": "p1", "unprivileged": true, "ha_replication_target": "n2"},
            "root_disk": {"size": 8}
          }
        }
      JSON
      etag = "mock-openbao-migrate-etag"
    }
  }

  assert {
    condition     = local.openbao_generated_containers["openbao-20"].migrate && local.openbao_generated_containers["openbao-20"].node_name == "n3" && local.openbao_generated_containers["openbao-20"].vm_id == 110020
    error_message = "The object-form peer must retain its identity and node while passing migrate=true."
  }

  assert {
    condition = (
      local.openbao_generated_containers["openbao-10"].migrate == null &&
      local.openbao_generated_containers["openbao-10"].ha_replication_target == "n2"
    )
    error_message = "A generated peer must pass its HA target and leave an omitted migrate value for target-aware resolution."
  }
}
