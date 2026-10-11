# OpenBao peers built from openbao_cluster.placement. An integer item is an
# ordinal suffix and keeps the "<prefix><NN>" key. An object item {"vm_id": N}
# takes "<app>-<vm_id>" as key and hostname unless it sets "hostname". Scoped
# to plan_options.target like the other root suites; see deployment_source.

mock_provider "aws" {}

run "integer_peers_keep_ordinal_identity" {
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
          "nodes": {"n1": {"role": "node-1", "cluster_roles": ["storage"]}},
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
            "placement": {"n1": [10, 20, {"vm_id": 110050}, {"vm_id": 110060, "hostname": "openbao-60"}]},
            "container_defaults": {"tags": ["openbao"], "pool_id": "p1", "unprivileged": true},
            "root_disk": {"size": 8}
          }
        }
      JSON
      etag = "mock-openbao-etag"
    }
  }

  assert {
    condition     = local.openbao_generated_containers["openbao-10"].vm_id == 110010 && local.openbao_generated_containers["openbao-10"].hostname == "openbao-10" && local.openbao_generated_containers["openbao-10"].ip_config.ipv4_address == "10.0.10.10/24"
    error_message = "Integer suffix 10 must keep the ordinal key openbao-10, vm_id 110010 and host octet .10."
  }

  assert {
    condition     = local.openbao_generated_containers["openbao-20"].vm_id == 110020 && local.openbao_generated_containers["openbao-20"].hostname == "openbao-20" && local.openbao_generated_containers["openbao-20"].ip_config.ipv4_address == "10.0.10.20/24"
    error_message = "Integer suffix 20 must keep the ordinal key openbao-20, vm_id 110020 and host octet .20."
  }

  assert {
    condition     = length(keys(local.openbao_generated_containers)) == 4
    error_message = "The placement above has four peers; the generator must emit exactly four containers."
  }
}

run "object_peer_takes_app_vm_id_name" {
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
          "nodes": {"n1": {"role": "node-1", "cluster_roles": ["storage"]}},
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
            "placement": {"n1": [{"vm_id": 110050}]},
            "container_defaults": {"tags": ["openbao"], "pool_id": "p1", "unprivileged": true},
            "root_disk": {"size": 8}
          }
        }
      JSON
      etag = "mock-openbao-etag"
    }
  }

  assert {
    condition     = contains(keys(local.openbao_generated_containers), "openbao-110050") && length(keys(local.openbao_generated_containers)) == 1
    error_message = "An object peer without hostname must be keyed openbao-110050, and be the only container emitted."
  }

  assert {
    condition     = local.openbao_generated_containers["openbao-110050"].vm_id == 110050 && local.openbao_generated_containers["openbao-110050"].hostname == "openbao-110050" && local.openbao_generated_containers["openbao-110050"].ip_config.ipv4_address == "10.0.10.50/24"
    error_message = "Object peer {vm_id = 110050} must have vm_id 110050, hostname openbao-110050, and host octet .50 (vm_id minus vm_id_base)."
  }
}

run "object_peer_explicit_hostname_wins" {
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
          "nodes": {"n1": {"role": "node-1", "cluster_roles": ["storage"]}},
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
            "placement": {"n1": [{"vm_id": 110060, "hostname": "openbao-60"}]},
            "container_defaults": {"tags": ["openbao"], "pool_id": "p1", "unprivileged": true},
            "root_disk": {"size": 8}
          }
        }
      JSON
      etag = "mock-openbao-etag"
    }
  }

  assert {
    condition     = contains(keys(local.openbao_generated_containers), "openbao-60") && !contains(keys(local.openbao_generated_containers), "openbao-110060")
    error_message = "An object peer with an explicit hostname must be keyed by that hostname, not by <app>-<vm_id>."
  }

  assert {
    condition     = local.openbao_generated_containers["openbao-60"].hostname == "openbao-60" && local.openbao_generated_containers["openbao-60"].vm_id == 110060 && local.openbao_generated_containers["openbao-60"].ip_config.ipv4_address == "10.0.10.60/24"
    error_message = "Explicit hostname must be the container hostname; vm_id stays 110060 and the host octet stays .60."
  }
}

# vm_id equal to vm_id_base yields host octet 0, which is not a peer.
run "object_peer_at_vm_id_base_fails" {
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
          "nodes": {"n1": {"role": "node-1", "cluster_roles": ["storage"]}},
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
            "placement": {"n1": [{"vm_id": 110000}]},
            "container_defaults": {"tags": ["openbao"], "pool_id": "p1", "unprivileged": true},
            "root_disk": {"size": 8}
          }
        }
      JSON
      etag = "mock-openbao-etag"
    }
  }

  expect_failures = [output.deployment_validated]
}

# Host octet 1 is conventionally the gateway; the 2..254 bound excludes it.
run "object_peer_octet_below_2_fails" {
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
          "nodes": {"n1": {"role": "node-1", "cluster_roles": ["storage"]}},
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
            "placement": {"n1": [{"vm_id": 110001}]},
            "container_defaults": {"tags": ["openbao"], "pool_id": "p1", "unprivileged": true},
            "root_disk": {"size": 8}
          }
        }
      JSON
      etag = "mock-openbao-etag"
    }
  }

  expect_failures = [output.deployment_validated]
}

# Host octet 300 is a real host on a /16, so cidrhost() builds the peer and only
# the 2..254 bound rejects it. On a /24 the generator would fail first.
run "object_peer_octet_above_254_fails" {
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
          "nodes": {"n1": {"role": "node-1", "cluster_roles": ["storage"]}},
          "pools": {"p1": {}},
          "proxmox_node": "n1",
          "proxmox_user": "root",
          "domain": "placement.example",
          "network_cidrs": {"lan_main": "10.0.0.0/24", "mgmt": "10.0.0.0/16"},
          "vm_ssh_public_key": "ssh-ed25519 AAAAtest fixture",
          "openbao_cluster": {
            "enabled": true,
            "name_prefix": "openbao-",
            "vm_id_base": 110000,
            "vlan": "mgmt",
            "placement": {"n1": [{"vm_id": 110300}]},
            "container_defaults": {"tags": ["openbao"], "pool_id": "p1", "unprivileged": true},
            "root_disk": {"size": 8}
          }
        }
      JSON
      etag = "mock-openbao-etag"
    }
  }

  expect_failures = [output.deployment_validated]
}
