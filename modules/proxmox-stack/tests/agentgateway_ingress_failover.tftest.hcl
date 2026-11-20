# The selected gateway members and the native health-failover route contract.
# Every run plans against mocked providers and synthetic addresses.

mock_provider "proxmox" {
  mock_data "proxmox_virtual_environment_datastores" {
    defaults = {
      datastores = [
        { id = "local", type = "dir", content_types = ["iso", "vztmpl", "backup"] },
        { id = "local-zfs", type = "zfspool", content_types = ["images", "rootdir"] },
      ]
    }
  }
}
mock_provider "tls" {}
mock_provider "random" {}
mock_provider "aws" {}
mock_provider "null" {}

override_module {
  target = module.storage
  outputs = {
    cloud_init_file_id   = null
    datastores_available = {}
    storage_validated    = true
  }
}

override_module {
  target = module.splunk_vm
  outputs = {
    vm_id      = 200
    name       = "splunk-example"
    ip_address = "192.0.2.200"
    tiered_disks = {
      fast = { datastore_id = "fast-example", interface = "virtio2", size = 1024, backup = true }
      bulk = { datastore_id = "bulk-example", interface = "virtio3", size = 2048, backup = false }
    }
  }
}

override_module {
  target = module.firewall
  outputs = {
    cluster_firewall_enabled            = true
    vm_firewall_enabled                 = true
    container_firewall_enabled          = true
    pipeline_container_firewall_enabled = true
  }
}

override_module {
  target = module.acme_certificates
  outputs = {
    acme_accounts = {}
    dns_plugins   = {}
    certificates  = {}
  }
}

variables {
  vm_ssh_public_key       = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestKeyData test@example.test"
  proxmox_user            = "root"
  proxmox_ssh_private_key = "-----BEGIN OPENSSH PRIVATE KEY-----\ntest\n-----END OPENSSH PRIVATE KEY-----"
  network_cidrs           = { for name, id in var.vlan_ids : name => "192.168.${id}.0/24" }
  domain                  = "example.test"
  nodes                   = { node-example = { role = "node-1" } }
}

run "selected_members_share_health_failover_and_keep_other_routes" {
  command = plan

  variables {
    containers = {
      agentgateway   = { vm_id = 141, node_name = "node-example", vlan = "ai", tags = ["agentgateway"] }
      agentgateway-2 = { vm_id = 142, node_name = "node-example", vlan = "ai", tags = ["agentgateway"] }
      agentgateway-3 = { vm_id = 143, node_name = "node-example", vlan = "ai", tags = ["agentgateway"] }
      vikunja        = { vm_id = 144, node_name = "node-example", vlan = "apps" }
      llm-router-fixture = {
        vm_id            = 145
        node_name        = "node-example"
        vlan             = "ai"
        tags             = ["llm-router"]
        memory_dedicated = 4096
      }
    }
  }

  assert {
    condition = (
      length(one([for r in output.ansible_inventory.ingress : r if r.name == "mcp"]).backends) == 1 &&
      one([for r in output.ansible_inventory.ingress : r if r.name == "mcp"]).backends[0] == local.container_address["agentgateway"] &&
      length(one([for r in output.ansible_inventory.ingress : r if r.name == "mcp"]).failover_fallback.backends) == 1 &&
      one([for r in output.ansible_inventory.ingress : r if r.name == "mcp"]).failover_fallback.backends[0] == local.container_address["agentgateway-2"]
    )
    error_message = "The MCP route must publish one named primary and one named fallback backend."
  }

  assert {
    condition = (
      length(one([for r in output.ansible_inventory.ingress : r if r.name == "mcp"]).backends) == 1 &&
      length(one([for r in output.ansible_inventory.ingress : r if r.name == "mcp"]).failover_fallback.backends) == 1 &&
      length(one([for r in output.ansible_inventory.ingress : r if r.name == "agentgateway"]).backends) == 1 &&
      length(one([for r in output.ansible_inventory.ingress : r if r.name == "agentgateway"]).failover_fallback.backends) == 1 &&
      one([for r in output.ansible_inventory.ingress : r if r.name == "mcp"]).backends[0] == one([for r in output.ansible_inventory.ingress : r if r.name == "agentgateway"]).backends[0] &&
      one([for r in output.ansible_inventory.ingress : r if r.name == "mcp"]).failover_fallback.backends[0] == one([for r in output.ansible_inventory.ingress : r if r.name == "agentgateway"]).failover_fallback.backends[0]
    )
    error_message = "Both aliases must use the same canonical singleton primary and fallback."
  }

  assert {
    condition = !contains(
      one([for r in output.ansible_inventory.ingress : r if r.name == "mcp"]).backends,
      local.container_address["agentgateway-3"],
      ) && !contains(
      one([for r in output.ansible_inventory.ingress : r if r.name == "mcp"]).failover_fallback.backends,
      local.container_address["agentgateway-3"],
      ) && !contains(
      one([for r in output.ansible_inventory.ingress : r if r.name == "agentgateway"]).backends,
      local.container_address["agentgateway-3"],
      ) && !contains(
      one([for r in output.ansible_inventory.ingress : r if r.name == "agentgateway"]).failover_fallback.backends,
      local.container_address["agentgateway-3"],
    )
    error_message = "Additional tagged instances must stay out of both alias memberships."
  }

  assert {
    condition = (
      one([for r in output.ansible_inventory.ingress : r if r.name == "mcp"]).port == local.pipeline_constants.service_ports.agentgateway_proxy &&
      !one([for r in output.ansible_inventory.ingress : r if r.name == "mcp"]).sso &&
      one([for r in output.ansible_inventory.ingress : r if r.name == "agentgateway"]).port == local.pipeline_constants.service_ports.agentgateway_admin &&
      one([for r in output.ansible_inventory.ingress : r if r.name == "agentgateway"]).sso
    )
    error_message = "Each alias must retain its existing traffic port and auth setting."
  }

  assert {
    condition = alltrue([
      for name in ["mcp", "agentgateway"] : one([
        for r in output.ansible_inventory.ingress : r
        if(
          r.name == name && r.health_check && r.health_check_path == "/metrics" &&
          r.health_check_port == local.pipeline_constants.service_ports.agentgateway_metrics &&
          r.failover_fallback.health_check_path == "/metrics" &&
          length(r.backends) == 1 && length(r.failover_fallback.backends) == 1
        )
      ]) != null
    ]) && !can(one([for r in output.ansible_inventory.ingress : r if r.name == "mcp"]).failover_fallback.errors)
    error_message = "Both aliases need singleton metrics-health failover without error-trigger replay."
  }

  assert {
    condition = (
      one([for r in output.ansible_inventory.ingress : r if r.name == "vikunja"]).ip == local.container_address["vikunja"] &&
      one([for r in output.ansible_inventory.ingress : r if r.name == "vikunja"]).port == local.pipeline_constants.service_ports.vikunja_web &&
      !one([for r in output.ansible_inventory.ingress : r if r.name == "vikunja"]).sso &&
      one([for r in output.ansible_inventory.ingress : r if r.name == "llm"]).backends == [local.container_address["llm-router-fixture"]] &&
      one([for r in output.ansible_inventory.ingress : r if r.name == "llm"]).strategy == "hrw"
    )
    error_message = "The ordinary Vikunja route and unrelated router pool must retain their existing outputs."
  }
}

run "zero_tagged_members_omit_gateway_routes" {
  command = plan

  variables {
    containers = {
      vikunja = { vm_id = 144, node_name = "node-example", vlan = "apps" }
    }
  }

  assert {
    condition = length([
      for r in output.ansible_inventory.ingress : r
      if contains(["mcp", "agentgateway"], r.name)
    ]) == 0 && one([for r in output.ansible_inventory.ingress : r if r.name == "vikunja"]).ip == local.container_address["vikunja"]
    error_message = "No gateway tags must omit both aliases while unrelated routes remain available."
  }
}

run "third_only_tag_fails_without_pool_fallback" {
  command         = plan
  expect_failures = [var.containers]

  variables {
    containers = {
      agentgateway-3 = { vm_id = 143, node_name = "node-example", vlan = "ai", tags = ["agentgateway"] }
    }
  }
}

run "docker_ai_pair_publishes_pooled_hatchet_routes" {
  command = plan

  variables {
    containers = {
      hatchet = {
        vm_id     = 150
        node_name = "node-example"
        vlan      = "ai"
        tags      = ["hatchet", "ai-orchestration", "docker"]
      }
      "hatchet-dashboard-fixture" = {
        vm_id     = 151
        node_name = "node-example"
        vlan      = "ai"
        tags      = ["docker-ai", "ai-orchestration", "docker", "managed-secrets"]
      }
      "hatchet-engine-fixture" = {
        vm_id     = 152
        node_name = "node-example"
        vlan      = "ai"
        tags      = ["docker-ai", "ai-orchestration", "docker", "managed-secrets"]
      }
    }
  }

  assert {
    condition = (
      length([for r in output.ansible_inventory.ingress : r if r.name == "hatchet"]) == 1 &&
      one([for r in output.ansible_inventory.ingress : r if r.name == "hatchet"]).backends == [
        local.container_address["hatchet-dashboard-fixture"],
        local.container_address["hatchet-engine-fixture"],
      ] &&
      one([for r in output.ansible_inventory.ingress : r if r.name == "hatchet"]).sso &&
      one([for r in output.ansible_inventory.ingress : r if r.name == "hatchet"]).health_check &&
      one([for r in output.ansible_inventory.ingress : r if r.name == "hatchet"]).health_check_path == "/api/ready"
    )
    error_message = "The docker-ai pool must publish exactly one SSO-gated Hatchet dashboard route with both sorted backends and /api/ready health."
  }

  assert {
    condition = (
      length([for r in output.ansible_inventory.ingress : r if r.name == "hatchet-engine"]) == 1 &&
      one([for r in output.ansible_inventory.ingress : r if r.name == "hatchet-engine"]).backends == [
        local.container_address["hatchet-dashboard-fixture"],
        local.container_address["hatchet-engine-fixture"],
      ] &&
      one([for r in output.ansible_inventory.ingress : r if r.name == "hatchet-engine"]).port == local.pipeline_constants.service_ports.hatchet_grpc &&
      one([for r in output.ansible_inventory.ingress : r if r.name == "hatchet-engine"]).scheme == "h2c" &&
      !one([for r in output.ansible_inventory.ingress : r if r.name == "hatchet-engine"]).sso &&
      one([for r in output.ansible_inventory.ingress : r if r.name == "hatchet-engine"]).health_check &&
      one([for r in output.ansible_inventory.ingress : r if r.name == "hatchet-engine"]).health_check_path == "/ready" &&
      one([for r in output.ansible_inventory.ingress : r if r.name == "hatchet-engine"]).health_check_scheme == "http" &&
      one([for r in output.ansible_inventory.ingress : r if r.name == "hatchet-engine"]).health_check_port == local.pipeline_constants.service_ports.hatchet_health &&
      output.ansible_inventory.constants.service_ports.hatchet_health == 8733
    )
    error_message = "The pooled Hatchet engine route must publish h2c, machine access, and its HTTP /ready probe on hatchet_health 8733."
  }

  assert {
    condition     = length([for r in output.ansible_inventory.ingress : r if r.name == "drawio"]) == 0
    error_message = "Docker AI guests must not publish Draw.io until one carries the next-ai-drawio service tag."
  }
}

run "legacy_hatchet_route_remains_when_docker_ai_pool_is_empty" {
  command = plan

  variables {
    containers = {
      hatchet = {
        vm_id     = 153
        node_name = "node-example"
        vlan      = "ai"
        tags      = ["hatchet", "ai-orchestration", "docker"]
      }
    }
  }

  assert {
    condition = (
      length([for r in output.ansible_inventory.ingress : r if r.name == "hatchet"]) == 1 &&
      one([for r in output.ansible_inventory.ingress : r if r.name == "hatchet"]).owner == "hatchet" &&
      one([for r in output.ansible_inventory.ingress : r if r.name == "hatchet"]).ip == local.container_address["hatchet"] &&
      one([for r in output.ansible_inventory.ingress : r if r.name == "hatchet"]).port == local.pipeline_constants.service_ports.hatchet_web &&
      one([for r in output.ansible_inventory.ingress : r if r.name == "hatchet"]).sso &&
      try(one([for r in output.ansible_inventory.ingress : r if r.name == "hatchet"]).health_check, null) == null &&
      try(one([for r in output.ansible_inventory.ingress : r if r.name == "hatchet"]).health_check_path, null) == null &&
      length([for r in output.ansible_inventory.ingress : r if r.name == "hatchet-engine"]) == 0
    )
    error_message = "With no docker-ai tags, the existing Hatchet guest must retain its one single-backend SSO web route."
  }
}

run "missing_fallback_key_fails_closed" {
  command         = plan
  expect_failures = [var.containers]

  variables {
    containers = {
      agentgateway = { vm_id = 141, node_name = "node-example", vlan = "ai", tags = ["agentgateway"] }
    }
  }
}

run "selected_key_without_tag_fails_closed" {
  command         = plan
  expect_failures = [var.containers]

  variables {
    containers = {
      agentgateway   = { vm_id = 141, node_name = "node-example", vlan = "ai", tags = ["terraform"] }
      agentgateway-2 = { vm_id = 142, node_name = "node-example", vlan = "ai", tags = ["agentgateway"] }
    }
  }
}

run "blank_selected_address_fails_inventory_publication_guard" {
  command         = plan
  expect_failures = [aws_s3_object.ansible_inventory]

  variables {
    containers = {
      agentgateway = {
        vm_id     = 141
        node_name = "node-example"
        vlan      = "ai"
        tags      = ["agentgateway"]
      }
      agentgateway-2 = {
        vm_id     = 142
        node_name = "node-example"
        vlan      = "ai"
        tags      = ["agentgateway"]
        ip_config = { ipv4_address = "" }
      }
    }
  }

  assert {
    condition     = local.container_address["agentgateway-2"] == ""
    error_message = "The blank static address must exercise the inventory publication precondition."
  }
}

run "next_ai_drawio_is_tag_derived_web_only_and_authelia_gated" {
  command = plan

  variables {
    containers = {
      "drawio-fixture" = {
        vm_id     = 153
        node_name = "node-example"
        vlan      = "ai"
        tags      = ["docker-ai", "next-ai-drawio", "ai-orchestration", "docker", "managed-secrets"]
      }
      "docker-ai-peer" = {
        vm_id     = 154
        node_name = "node-example"
        vlan      = "ai"
        tags      = ["docker-ai", "ai-orchestration", "docker", "managed-secrets"]
      }
      "llm-router-fixture" = {
        vm_id            = 155
        node_name        = "node-example"
        vlan             = "ai"
        tags             = ["llm-router"]
        memory_dedicated = 4096
      }
      "ingress-fixture" = {
        vm_id     = 156
        node_name = "node-example"
        vlan      = "mgmt"
        dhcp      = true
        tags      = ["ingress"]
      }
    }
  }

  assert {
    condition = (
      output.ansible_inventory.constants.service_ports.next_ai_drawio_web == 3070 &&
      output.ansible_inventory.constants.service_ports.next_ai_drawio_mcp == 3071 &&
      local.next_ai_drawio_container_ids == { "drawio-fixture" = 153 } &&
      local.next_ai_drawio_ingress_src == join(",", local.ingress_hosts) &&
      local.next_ai_drawio_mcp_src == local.container_address["llm-router-fixture"]
    )
    error_message = "Next AI Draw.io ports and firewall selection must be published from their constants and service tag."
  }

  assert {
    condition = (
      length([for r in output.ansible_inventory.ingress : r if r.name == "drawio"]) == 1 &&
      one([for r in output.ansible_inventory.ingress : r if r.name == "drawio"]).backends == [
        for k in sort(keys(local.next_ai_drawio_container_ids)) : local.container_address[k]
      ] &&
      one([for r in output.ansible_inventory.ingress : r if r.name == "drawio"]).port == local.pipeline_constants.service_ports.next_ai_drawio_web &&
      one([for r in output.ansible_inventory.ingress : r if r.name == "drawio"]).sso &&
      length([for r in output.ansible_inventory.ingress : r if r.port == local.pipeline_constants.service_ports.next_ai_drawio_mcp]) == 0
    )
    error_message = "Only the tagged Draw.io web listener may be routed, and it must remain Authelia-gated."
  }
}

run "next_ai_drawio_ineligible_tag_fails_inventory_publication_guard" {
  command         = plan
  expect_failures = [aws_s3_object.ansible_inventory]

  variables {
    containers = {
      "ineligible-drawio" = {
        vm_id     = 157
        node_name = "node-example"
        vlan      = "ai"
        tags      = ["next-ai-drawio"]
      }
    }
  }
}

run "second_next_ai_drawio_tag_fails_inventory_publication_guard" {
  command         = plan
  expect_failures = [aws_s3_object.ansible_inventory]

  variables {
    containers = {
      "drawio-fixture" = {
        vm_id     = 153
        node_name = "node-example"
        vlan      = "ai"
        tags      = ["docker-ai", "next-ai-drawio", "ai-orchestration"]
      }
      "drawio-second" = {
        vm_id     = 158
        node_name = "node-example"
        vlan      = "ai"
        tags      = ["docker-ai", "next-ai-drawio", "ai-orchestration"]
      }
    }
  }
}
