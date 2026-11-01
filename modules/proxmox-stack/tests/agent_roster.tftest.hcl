# Tests for the optional agent roster projection.
# All runs use mocked providers and plan only.

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
    vm_id       = 200
    name        = "splunk-example"
    ip_address  = "192.0.2.200"
    mac_address = "BC:24:11:00:00:C8"
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

run "agent_roster_projects_two_agents" {
  command = plan

  variables {
    containers = {
      "agent-example-1" = { vm_id = 240, node_name = "node-example", vlan = "apps" }
      "agent-example-2" = { vm_id = 241, hostname = "agent-two.example.test", node_name = "node-example", vlan = "apps" }
    }
    agents = {
      "agent-example-1" = {
        name = "research-scout", display = "Scout", purpose = "Search example records"
      }
      "agent-example-2" = {
        name             = "support-guide", display = "Guide", purpose = "Answer example requests"
        owns             = ["splunk"]
        router_key_class = "zdr"
        trust_tier       = "trusted"
        slack = {
          home_channel     = "agent-home-example"
          requests_channel = "agent-requests-example"
        }
      }
    }
  }

  assert {
    condition     = sort(keys(output.ansible_inventory.agents)) == tolist(["research-scout", "support-guide"])
    error_message = "The agents inventory map must be keyed by agent.name."
  }

  assert {
    condition = (
      local.agent_firewall_containers["research-scout"].vm_id == 240 &&
      length(local.agent_firewall_containers["research-scout"].owns) == 0 &&
      local.agent_firewall_containers["support-guide"].vm_id == 241 &&
      local.agent_firewall_containers["support-guide"].owns == tolist(["splunk"]) &&
      toset(keys(local.agent_system_port_catalog)) == toset(local.agent_systems) &&
      toset(keys(local.agent_system_hosts)) == toset(local.agent_systems)
    )
    error_message = "The firewall projection must carry roster vm_ids and owns, with aligned system port and host catalogs."
  }

  assert {
    condition = (
      output.ansible_inventory.agents["research-scout"].container == "agent-example-1" &&
      output.ansible_inventory.agents["research-scout"].hostname == "agent-example-240" &&
      output.ansible_inventory.agents["research-scout"].display == "Scout" &&
      output.ansible_inventory.agents["research-scout"].purpose == "Search example records" &&
      length(output.ansible_inventory.agents["research-scout"].owns) == 0 &&
      output.ansible_inventory.agents["research-scout"].router_key_class == "standard" &&
      output.ansible_inventory.agents["research-scout"].trust_tier == "untrusted" &&
      sort(keys(output.ansible_inventory.agents["research-scout"])) == tolist(["container", "display", "hostname", "owns", "purpose", "router_key_class", "trust_tier"])
    )
    error_message = "The roster entry must include its container, hostname, required fields, and defaults without Slack."
  }

  assert {
    condition = (
      output.ansible_inventory.agents["support-guide"].container == "agent-example-2" &&
      output.ansible_inventory.agents["support-guide"].hostname == "agent-two.example.test" &&
      output.ansible_inventory.agents["support-guide"].display == "Guide" &&
      output.ansible_inventory.agents["support-guide"].purpose == "Answer example requests" &&
      output.ansible_inventory.agents["support-guide"].owns == tolist(["splunk"]) &&
      output.ansible_inventory.agents["support-guide"].router_key_class == "zdr" &&
      output.ansible_inventory.agents["support-guide"].trust_tier == "trusted" &&
      sort(keys(output.ansible_inventory.agents["support-guide"])) == tolist(["container", "display", "hostname", "owns", "purpose", "router_key_class", "slack", "trust_tier"]) &&
      output.ansible_inventory.agents["support-guide"].slack.home_channel == "agent-home-example" &&
      output.ansible_inventory.agents["support-guide"].slack.requests_channel == "agent-requests-example"
    )
    error_message = "The roster entry with Slack must preserve its source container, hostname, fields, and optional channels."
  }
}

run "logical_owner_is_published_without_physical_identity" {
  command = plan

  variables {
    agents = {
      "example-owner" = {
        display            = "Example Owner"
        purpose            = "Exercise the logical owner projection"
        owns               = ["example-domain"]
        router_key_class   = "standard"
        trust_tier         = "untrusted"
        native_binding_ref = "tests/runtime/example-owner"
        specializations = [
          { name = "example-search", description = "Synthetic fixture specialization" }
        ]
      }
    }
  }

  assert {
    condition = (
      output.ansible_inventory.schema_version == "2.8.0" &&
      sort(keys(output.ansible_inventory.agents)) == tolist(["example-owner"]) &&
      output.ansible_inventory.agents["example-owner"].display == "Example Owner" &&
      output.ansible_inventory.agents["example-owner"].owns == tolist(["example-domain"]) &&
      output.ansible_inventory.agents["example-owner"].trust_tier == "untrusted" &&
      output.ansible_inventory.agents["example-owner"].native_binding_ref == "tests/runtime/example-owner" &&
      length(output.ansible_inventory.agents["example-owner"].specializations) == 1 &&
      !contains(keys(output.ansible_inventory.agents["example-owner"]), "container") &&
      !contains(keys(output.ansible_inventory.agents["example-owner"]), "hostname") &&
      local.agent_firewall_containers == {} &&
      output.ansible_inventory.hermes_agents == {}
    )
    error_message = "A logical owner must publish its owner metadata and specializations without becoming a guest or Hermes endpoint."
  }
}

run "logical_owner_without_specializations_publishes_an_empty_array" {
  command = plan

  variables {
    agents = {
      "example-owner" = {
        display            = "Example Owner"
        purpose            = "Exercise the logical owner default"
        owns               = ["example-domain"]
        trust_tier         = "trusted"
        native_binding_ref = "tests/runtime/example-owner"
      }
    }
  }

  assert {
    condition = (
      length(output.ansible_inventory.agents["example-owner"].specializations) == 0 &&
      sort(keys(output.ansible_inventory.agents["example-owner"])) == tolist([
        "display", "native_binding_ref", "owns", "purpose", "router_key_class", "specializations", "trust_tier"
      ])
    )
    error_message = "Logical owners must always publish a specializations array, using an empty list when none is supplied."
  }
}

run "agent_and_workstation_maps_default_to_empty" {
  command = plan

  variables {
    containers = {
      "agent-example-1" = { vm_id = 240, node_name = "node-example", vlan = "apps" }
    }
  }

  assert {
    condition     = output.ansible_inventory.agents == {} && output.agents == {} && local.agent_firewall_containers == {} && length(output.ansible_inventory.workstations) == 0
    error_message = "The optional agent roster and workstation inventory default to empty maps."
  }
}

run "workstations_are_published" {
  command = plan

  variables {
    workstations = {
      "mac-primary" = {
        host  = "mac-primary.example.com"
        roles = ["mac-primary-serving"]
      }
      "mac-secondary" = {
        host  = "mac-secondary.example.com"
        roles = ["mac-secondary-serving"]
      }
    }
  }

  assert {
    condition     = jsonencode(output.ansible_inventory.workstations) == jsonencode(var.workstations)
    error_message = "The published inventory must preserve each deployment workstation host and role list."
  }
}

run "agent_owns_may_use_an_open_slug_outside_the_firewall_catalog" {
  command = plan

  variables {
    containers = {
      "agent-example-1" = { vm_id = 240, node_name = "node-example", vlan = "apps" }
    }
    agents = {
      "agent-example-1" = {
        name = "research-scout", display = "Scout", purpose = "Search example records", owns = ["example-domain"]
      }
    }
  }

  assert {
    condition = (
      output.agents["research-scout"].owns == tolist(["example-domain"]) &&
      length(local.agent_firewall_containers["research-scout"].owns) == 0
    )
    error_message = "Open ownership slugs must publish as metadata without generating uncataloged firewall rules."
  }
}

run "agent_container_must_not_have_a_firewall_profile_tag" {
  command = plan

  variables {
    containers = {
      "agent-example-1" = {
        vm_id = 240, node_name = "node-example", vlan = "apps"
        tags  = ["hermes-agent", "chromium", "hindsight-client", "firecrawl-client"]
      }
    }
    agents = {
      "agent-example-1" = { name = "research-scout", display = "Scout", purpose = "Search example records" }
    }
  }

  expect_failures = [output.agents]
}

run "agent_owned_system_rejects_a_dhcp_splunk_host" {
  command = plan

  variables {
    network_cidrs = { for vlan in keys(var.vlan_ids) : vlan => "192.0.2.0/24" }
    containers = {
      "agent-example-1" = { vm_id = 241, node_name = "node-example", vlan = "apps" }
      "splunk-dhcp-example" = {
        vm_id = 242, node_name = "node-example", vlan = "apps", dhcp = true, tags = ["splunk"]
      }
    }
    agents = {
      "agent-example-1" = {
        name = "research-scout", display = "Scout", purpose = "Search example records", owns = ["splunk"]
      }
    }
  }

  expect_failures = [output.agents]
}

run "agent_system_hosts_cribl_contains_only_static_stream_guests" {
  command = plan

  variables {
    network_cidrs = { for vlan in keys(var.vlan_ids) : vlan => "192.0.2.0/24" }
    containers = {
      "cribl-static-example" = {
        vm_id = 241, node_name = "node-example", vlan = "apps", tags = ["cribl", "stream"]
      }
      "cribl-dhcp-example" = {
        vm_id = 242, node_name = "node-example", vlan = "apps", dhcp = true, tags = ["cribl", "stream"]
      }
    }
  }

  assert {
    condition     = local.agent_system_hosts["cribl"] == ["192.0.2.241"]
    error_message = "Cribl host addresses must include only static Cribl Stream guests."
  }
}

run "agent_container_must_not_have_hindsight_tag" {
  command = plan

  variables {
    containers = {
      "agent-example-1" = {
        vm_id = 240, node_name = "node-example", vlan = "apps"
        tags  = ["hindsight"]
      }
    }
    agents = {
      "agent-example-1" = { name = "research-scout", display = "Scout", purpose = "Search example records" }
    }
  }

  expect_failures = [output.agents]
}

run "agent_container_must_not_have_pooled_backend_tag" {
  command = plan

  variables {
    containers = {
      "agent-example-1" = {
        vm_id = 240, node_name = "node-example", vlan = "apps"
        tags  = ["zammad"]
      }
    }
    agents = {
      "agent-example-1" = { name = "research-scout", display = "Scout", purpose = "Search example records" }
    }
  }

  expect_failures = [output.agents]
}

run "agent_container_must_not_have_validation_profile_tag" {
  command = plan

  variables {
    containers = {
      "agent-example-1" = {
        vm_id = 240, node_name = "node-example", vlan = "apps"
        tags  = ["ai-runner", "ai-proxied"]
      }
    }
    agents = {
      "agent-example-1" = { name = "research-scout", display = "Scout", purpose = "Search example records" }
    }
  }

  expect_failures = [output.agents]
}

run "agent_with_cataloged_ownership_passes" {
  command = plan

  variables {
    containers = {
      "agent-example-1" = { vm_id = 240, node_name = "node-example", vlan = "apps" }
    }
    agents = {
      "agent-example-1" = {
        name = "research-scout", display = "Scout", purpose = "Search example records", owns = ["splunk"]
      }
    }
  }

  assert {
    condition     = output.agents["research-scout"].owns == tolist(["splunk"])
    error_message = "A roster entry can own a system present in the port catalog."
  }
}

run "agent_names_must_be_unique" {
  command = plan

  variables {
    containers = {
      "agent-example-1" = { vm_id = 240, node_name = "node-example", vlan = "apps" }
      "agent-example-2" = { vm_id = 241, node_name = "node-example", vlan = "apps" }
    }
    agents = {
      "agent-example-1" = { name = "research-scout", display = "Scout", purpose = "Search records" }
      "agent-example-2" = { name = "research-scout", display = "Guide", purpose = "Answer requests" }
    }
  }

  expect_failures = [output.agents]
}

run "agent_displays_must_be_unique" {
  command = plan

  variables {
    containers = {
      "agent-example-1" = { vm_id = 240, node_name = "node-example", vlan = "apps" }
    }
    agents = {
      "agent-example-1" = { name = "research-scout", display = "Scout", purpose = "Search records" }
      "example-owner" = {
        display    = "Scout", purpose = "Own example domain"
        trust_tier = "trusted", native_binding_ref = "tests/runtime/example-owner"
      }
    }
  }

  expect_failures = [output.agents]
}

run "agent_owns_values_must_be_unique_across_agents" {
  command = plan

  variables {
    containers = {
      "agent-example-1" = { vm_id = 240, node_name = "node-example", vlan = "apps" }
      "agent-example-2" = { vm_id = 241, node_name = "node-example", vlan = "apps" }
    }
    agents = {
      "agent-example-1" = { name = "research-scout", display = "Scout", purpose = "Search records", owns = ["cribl"] }
      "agent-example-2" = { name = "support-guide", display = "Guide", purpose = "Answer requests", owns = ["cribl"] }
    }
  }

  expect_failures = [output.agents]
}

run "agent_owns_values_must_be_unique_across_physical_and_logical_owners" {
  command = plan

  variables {
    containers = {
      "agent-example-1" = { vm_id = 240, node_name = "node-example", vlan = "apps" }
    }
    agents = {
      "agent-example-1" = {
        name = "research-scout", display = "Scout", purpose = "Search records", owns = ["example-domain"]
      }
      "example-owner" = {
        display    = "Example Owner", purpose = "Own example domain", owns = ["example-domain"]
        trust_tier = "trusted", native_binding_ref = "tests/runtime/example-owner"
      }
    }
  }

  expect_failures = [output.agents]
}

run "logical_owner_key_must_not_collide_with_physical_owner_name" {
  command = plan

  variables {
    containers = {
      "agent-example-1" = { vm_id = 240, node_name = "node-example", vlan = "apps" }
    }
    agents = {
      "agent-example-1" = {
        name = "example-owner", display = "Physical Owner", purpose = "Physical example owner"
      }
      "example-owner" = {
        display    = "Logical Owner", purpose = "Logical example owner"
        trust_tier = "trusted", native_binding_ref = "tests/runtime/example-owner"
      }
    }
  }

  expect_failures = [output.agents]
}

run "agent_name_must_match_function_persona_pattern" {
  command = plan

  variables {
    containers = {
      "agent-example-1" = { vm_id = 240, node_name = "node-example", vlan = "apps" }
    }
    agents = {
      "agent-example-1" = { name = "Research-Scout", display = "Scout", purpose = "Search records" }
    }
  }

  expect_failures = [var.agents]
}

run "agent_trust_tier_must_be_valid" {
  command = plan

  variables {
    agents = {
      "agent-example-1" = { name = "research-scout", display = "Scout", purpose = "Search records", trust_tier = "bogus" }
    }
  }

  expect_failures = [var.agents]
}

run "logical_owner_requires_explicit_trust_tier_and_native_binding_ref" {
  command = plan

  variables {
    agents = {
      "example-owner" = {
        display = "Example Owner", purpose = "Exercise the logical owner guard"
      }
    }
  }

  expect_failures = [var.agents]
}

run "logical_owner_key_must_match_open_slug_pattern" {
  command = plan

  variables {
    agents = {
      "Example Owner" = {
        display    = "Example Owner", purpose = "Exercise the owner-key guard"
        trust_tier = "trusted", native_binding_ref = "tests/runtime/example-owner"
      }
    }
  }

  expect_failures = [var.agents]
}

run "logical_owner_native_binding_ref_must_be_nonblank" {
  command = plan

  variables {
    agents = {
      "example-owner" = {
        display    = "Example Owner", purpose = "Exercise the binding-reference guard"
        trust_tier = "trusted", native_binding_ref = "  "
      }
    }
  }

  expect_failures = [var.agents]
}

run "logical_owner_native_binding_ref_must_not_be_a_protocol_uri" {
  command = plan

  variables {
    agents = {
      "example-owner" = {
        display    = "Example Owner", purpose = "Exercise the binding-reference guard"
        trust_tier = "trusted", native_binding_ref = "mcp://example-owner"
      }
    }
  }

  expect_failures = [var.agents]
}

run "blank_physical_name_is_not_a_logical_owner_discriminator" {
  command = plan

  variables {
    agents = {
      "example-owner" = {
        name       = "", display = "Example Owner", purpose = "Exercise the name guard"
        trust_tier = "trusted", native_binding_ref = "tests/runtime/example-owner"
      }
    }
  }

  expect_failures = [var.agents]
}

run "logical_owner_specialization_names_must_be_unique" {
  command = plan

  variables {
    agents = {
      "example-owner" = {
        display    = "Example Owner", purpose = "Exercise specialization validation"
        trust_tier = "trusted", native_binding_ref = "tests/runtime/example-owner"
        specializations = [
          { name = "example-search", description = "First synthetic specialization" },
          { name = "example-search", description = "Duplicate synthetic specialization" }
        ]
      }
    }
  }

  expect_failures = [var.agents]
}

run "agent_owns_values_must_match_slug_pattern" {
  command = plan

  variables {
    containers = {
      "agent-example-1" = { vm_id = 240, node_name = "node-example", vlan = "apps" }
    }
    agents = {
      "agent-example-1" = { name = "research-scout", display = "Scout", purpose = "Search records", owns = ["Example Records"] }
    }
  }

  expect_failures = [var.agents]
}

run "agent_roster_keys_must_be_container_keys" {
  command = plan

  variables {
    containers = {
      "agent-example-1" = { vm_id = 240, node_name = "node-example", vlan = "apps" }
    }
    agents = {
      "unknown-example" = { name = "research-scout", display = "Scout", purpose = "Search records" }
    }
  }

  expect_failures = [output.agents]
}
