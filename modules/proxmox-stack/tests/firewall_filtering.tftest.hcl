# Tests for tag-based container filtering locals
#
# Verifies that pipeline_container_ids and notification_container_ids
# correctly include/exclude containers based on their tags.
#
# All runs use mock providers (no real infrastructure needed).
# command = plan is sufficient since locals are evaluated at plan time.

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
# aws is only used by the S3 inventory publish (inventory_publish.tf);
# mock it so tests need no AWS credentials in CI or locally.
mock_provider "aws" {}
mock_provider "null" {}

# Override data sources and modules that require real provider connections
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
    name        = "splunk-vm"
    ip_address  = "192.168.40.200"
    mac_address = "BC:24:11:00:00:C8"
    tiered_disks = {
      fast = { datastore_id = "fast-splunk", interface = "virtio2", size = 1024, backup = true }
      bulk = { datastore_id = "bulk-splunk", interface = "virtio3", size = 2048, backup = false }
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
  vm_ssh_public_key       = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestKeyData test@test"
  proxmox_ssh_private_key = "-----BEGIN OPENSSH PRIVATE KEY-----\ntest\n-----END OPENSSH PRIVATE KEY-----"
  # vlan_ids uses its variable default (single source of truth); network_cidrs is
  # derived from it as 192.168.<vlan_id>.0/24 — no duplicated VLAN/CIDR list.
  network_cidrs = { for name, id in var.vlan_ids : name => "192.168.${id}.0/24" }
}

# --- pipeline_container_ids tests ---

run "haproxy_tagged_container_in_pipeline_ids" {
  command = plan

  variables {
    containers = {
      "haproxy" = {
        vm_id    = 421040
        dhcp     = true
        hostname = "haproxy"
        vlan     = "siem"
        tags     = ["terraform", "haproxy", "container"]
      }
    }
  }

  assert {
    condition     = contains(keys(local.pipeline_container_ids), "haproxy")
    error_message = "Container with 'haproxy' tag must be in pipeline_container_ids"
  }

  assert {
    condition     = local.pipeline_container_ids["haproxy"] == 421040
    error_message = "pipeline_container_ids['haproxy'] should be vm_id 421040"
  }
}

run "cribl_edge_tagged_container_in_pipeline_ids" {
  command = plan

  variables {
    containers = {
      "cribl-edge" = {
        vm_id    = 423040
        dhcp     = true
        hostname = "cribl-edge"
        vlan     = "siem"
        tags     = ["terraform", "cribl", "edge", "container"]
      }
    }
  }

  assert {
    condition     = contains(keys(local.pipeline_container_ids), "cribl-edge")
    error_message = "Container with 'cribl' + 'edge' tags must be in pipeline_container_ids"
  }

  assert {
    condition     = local.pipeline_container_ids["cribl-edge"] == 423040
    error_message = "pipeline_container_ids['cribl-edge'] should be vm_id 423040"
  }
}

run "notifications_tagged_container_in_notification_ids" {
  command = plan

  variables {
    containers = {
      "mailpit" = {
        vm_id    = 185
        hostname = "mailpit"
        vlan     = "apps"
        tags     = ["terraform", "notifications", "container"]
      }
    }
  }

  assert {
    condition     = contains(keys(local.notification_container_ids), "mailpit")
    error_message = "Container with 'notifications' tag must be in notification_container_ids"
  }

  assert {
    condition     = local.notification_container_ids["mailpit"] == 185
    error_message = "notification_container_ids['mailpit'] should be vm_id 185"
  }

  assert {
    condition     = !contains(keys(local.pipeline_container_ids), "mailpit")
    error_message = "Container with only 'notifications' tag must NOT be in pipeline_container_ids"
  }
}

run "database_tagged_container_in_neither_set" {
  command = plan

  variables {
    containers = {
      "postgres" = {
        vm_id    = 170
        hostname = "postgres"
        vlan     = "data"
        tags     = ["terraform", "database", "container"]
      }
    }
  }

  assert {
    condition     = !contains(keys(local.pipeline_container_ids), "postgres")
    error_message = "Container with 'database' tag must NOT be in pipeline_container_ids"
  }

  assert {
    condition     = !contains(keys(local.notification_container_ids), "postgres")
    error_message = "Container with 'database' tag must NOT be in notification_container_ids"
  }
}

run "empty_containers_both_sets_empty" {
  command = plan

  variables {
    containers = {}
  }

  assert {
    condition     = length(local.pipeline_container_ids) == 0
    error_message = "pipeline_container_ids should be empty when containers is empty"
  }

  assert {
    condition     = length(local.notification_container_ids) == 0
    error_message = "notification_container_ids should be empty when containers is empty"
  }
}

run "cribl_without_edge_not_in_pipeline_ids" {
  command = plan

  variables {
    containers = {
      "cribl-stream" = {
        vm_id    = 425040
        dhcp     = true
        hostname = "cribl-stream"
        vlan     = "siem"
        tags     = ["terraform", "cribl", "stream", "container"]
      }
    }
  }

  assert {
    condition     = !contains(keys(local.pipeline_container_ids), "cribl-stream")
    error_message = "Container with 'cribl' but NOT 'edge' tag must NOT be in pipeline_container_ids"
  }
}

# --- cribl_stream_container_ids tests ---

run "cribl_stream_tagged_container_in_cribl_stream_ids" {
  command = plan

  variables {
    containers = {
      "cribl-stream" = {
        vm_id    = 425040
        dhcp     = true
        hostname = "cribl-stream"
        vlan     = "siem"
        tags     = ["terraform", "cribl", "stream", "pipeline", "container"]
      }
    }
  }

  assert {
    condition     = contains(keys(local.cribl_stream_container_ids), "cribl-stream")
    error_message = "Container with 'cribl' + 'stream' tags must be in cribl_stream_container_ids"
  }

  assert {
    condition     = local.cribl_stream_container_ids["cribl-stream"] == 425040
    error_message = "cribl_stream_container_ids['cribl-stream'] should be vm_id 425040"
  }

  assert {
    condition     = !contains(keys(local.pipeline_container_ids), "cribl-stream")
    error_message = "Cribl Stream must NOT be in pipeline_container_ids (it doesn't receive external traffic)"
  }
}

run "cribl_edge_not_in_cribl_stream_ids" {
  command = plan

  variables {
    containers = {
      "cribl-edge-01" = {
        vm_id    = 423040
        dhcp     = true
        hostname = "cribl-edge-01"
        vlan     = "siem"
        tags     = ["terraform", "cribl", "edge", "pipeline", "container"]
      }
    }
  }

  assert {
    condition     = !contains(keys(local.cribl_stream_container_ids), "cribl-edge-01")
    error_message = "Container with 'cribl' + 'edge' tags must NOT be in cribl_stream_container_ids"
  }

  assert {
    condition     = contains(keys(local.pipeline_container_ids), "cribl-edge-01")
    error_message = "Container with 'cribl' + 'edge' tags must be in pipeline_container_ids"
  }
}

# --- s3_container_ids tests ---

run "object_storage_tagged_container_in_s3_ids" {
  command = plan

  variables {
    containers = {
      "s3" = {
        vm_id    = 990004
        hostname = "object-storage"
        vlan     = "siem"
        dhcp     = true
        tags     = ["terraform", "container", "object-storage", "storage", "infrastructure"]
      }
    }
  }

  assert {
    condition     = contains(keys(local.s3_container_ids), "s3")
    error_message = "Container with 'object-storage' tag must be in s3_container_ids"
  }

  assert {
    condition     = local.s3_container_ids["s3"] == 990004
    error_message = "s3_container_ids['s3'] should be vm_id 990004"
  }

  assert {
    condition     = !contains(keys(local.pipeline_container_ids), "s3")
    error_message = "Container with 'object-storage' tag must NOT be in pipeline_container_ids"
  }

  assert {
    condition     = !contains(keys(local.notification_container_ids), "s3")
    error_message = "Container with 'object-storage' tag must NOT be in notification_container_ids"
  }
}

run "pipeline_and_stream_containers_mutually_exclusive" {
  command = plan

  variables {
    containers = {
      "haproxy" = {
        vm_id    = 421040
        dhcp     = true
        hostname = "haproxy"
        vlan     = "siem"
        tags     = ["terraform", "haproxy", "pipeline", "container"]
      }
      "cribl-edge-01" = {
        vm_id    = 423040
        dhcp     = true
        hostname = "cribl-edge-01"
        vlan     = "siem"
        tags     = ["terraform", "cribl", "edge", "pipeline", "container"]
      }
      "cribl-stream" = {
        vm_id    = 425040
        dhcp     = true
        hostname = "cribl-stream"
        vlan     = "siem"
        tags     = ["terraform", "cribl", "stream", "pipeline", "container"]
      }
    }
  }

  assert {
    condition     = length(local.pipeline_container_ids) == 2
    error_message = "pipeline_container_ids should contain haproxy + cribl-edge-01 (2 total)"
  }

  assert {
    condition     = length(local.cribl_stream_container_ids) == 1
    error_message = "cribl_stream_container_ids should contain only cribl-stream (1 total)"
  }

  assert {
    condition     = length(setintersection(keys(local.pipeline_container_ids), keys(local.cribl_stream_container_ids))) == 0
    error_message = "pipeline_container_ids and cribl_stream_container_ids must be mutually exclusive"
  }
}

# --- idrac_kvm_container_ids tests ---

run "idrac_tagged_container_in_idrac_kvm_container_ids" {
  command = plan

  variables {
    containers = {
      "idrac-kvm" = {
        vm_id    = 251
        hostname = "idrac-kvm"
        vlan     = "apps"
        tags     = ["terraform", "container", "idrac", "oob", "management", "docker"]
      }
    }
  }

  assert {
    condition     = contains(keys(local.idrac_kvm_container_ids), "idrac-kvm")
    error_message = "container with 'idrac' tag must be in idrac_kvm_container_ids"
  }

  assert {
    condition     = local.idrac_kvm_container_ids["idrac-kvm"] == 251
    error_message = "idrac_kvm_container_ids['idrac-kvm'] should be vm_id 251"
  }
}

run "non_idrac_container_not_in_idrac_kvm_container_ids" {
  command = plan

  variables {
    containers = {
      "mailpit" = {
        vm_id    = 110
        hostname = "mailpit"
        vlan     = "apps"
        tags     = ["terraform", "container", "notifications", "docker"]
      }
    }
  }

  assert {
    condition     = !contains(keys(local.idrac_kvm_container_ids), "mailpit")
    error_message = "container without 'idrac' tag must NOT be in idrac_kvm_container_ids"
  }

  assert {
    condition     = length(local.idrac_kvm_container_ids) == 0
    error_message = "idrac_kvm_container_ids should be empty when no containers have the 'idrac' tag"
  }
}

# --- honeypot_container_ids / honeypot_notify_container_ids tests ---

run "honeypot_tagged_containers_split_tripwire_vs_notify" {
  command = plan

  variables {
    containers = {
      "honeypot-tw-apps" = {
        vm_id    = 695000
        hostname = "honeypot-tw-apps"
        vlan     = "apps"
        dhcp     = true
        tags     = ["terraform", "container", "honeypot", "docker"]
      }
      "honeypot-notify" = {
        vm_id    = 492000
        hostname = "honeypot-notify"
        vlan     = "mgmt"
        dhcp     = true
        tags     = ["terraform", "container", "honeypot", "notify", "docker"]
      }
    }
  }

  # Both honeypot guests are in the base map.
  assert {
    condition     = contains(keys(local.honeypot_container_ids), "honeypot-tw-apps") && contains(keys(local.honeypot_container_ids), "honeypot-notify")
    error_message = "both honeypot-tagged guests must be in honeypot_container_ids"
  }

  # Only the notify gateway is in the notify subset.
  assert {
    condition     = contains(keys(local.honeypot_notify_container_ids), "honeypot-notify") && !contains(keys(local.honeypot_notify_container_ids), "honeypot-tw-apps")
    error_message = "only the honeypot+notify guest belongs to honeypot_notify_container_ids"
  }

  # A honeypot guest must never be double-claimed by the Mailpit/ntfy notification map.
  assert {
    condition     = !contains(keys(local.notification_container_ids), "honeypot-notify")
    error_message = "honeypot notify gateway must not also land in notification_container_ids (would create duplicate firewall_options)"
  }
}

run "non_honeypot_container_not_in_honeypot_ids" {
  command = plan

  variables {
    containers = {
      "mailpit" = {
        vm_id    = 110
        hostname = "mailpit"
        vlan     = "apps"
        tags     = ["terraform", "container", "notifications", "docker"]
      }
    }
  }

  assert {
    condition     = length(local.honeypot_container_ids) == 0 && length(local.honeypot_notify_container_ids) == 0
    error_message = "honeypot maps must be empty when no containers carry the 'honeypot' tag"
  }
}

# --- postgres_container_ids / nautobot_container_ids tests (issue #138) ---

run "postgres_and_nautobot_tags_filter_correctly" {
  command = plan

  variables {
    containers = {
      "postgres" = {
        vm_id    = 303000
        hostname = "postgres"
        vlan     = "data"
        dhcp     = true
        tags     = ["terraform", "container", "postgres"]
      }
      "nautobot" = {
        vm_id    = 605000
        hostname = "nautobot"
        vlan     = "apps"
        dhcp     = true
        tags     = ["terraform", "container", "nautobot"]
      }
    }
  }

  assert {
    condition     = local.postgres_container_ids["postgres"] == 303000 && length(local.postgres_container_ids) == 1
    error_message = "postgres-tagged container must be the sole member of postgres_container_ids"
  }

  assert {
    condition     = local.nautobot_container_ids["nautobot"] == 605000 && length(local.nautobot_container_ids) == 1
    error_message = "nautobot-tagged container must be the sole member of nautobot_container_ids"
  }

  # The two maps must not cross-claim, and neither belongs in the pipeline set.
  assert {
    condition     = !contains(keys(local.nautobot_container_ids), "postgres") && !contains(keys(local.postgres_container_ids), "nautobot")
    error_message = "postgres_container_ids and nautobot_container_ids must not cross-claim guests"
  }

  assert {
    condition     = !contains(keys(local.pipeline_container_ids), "postgres") && !contains(keys(local.pipeline_container_ids), "nautobot")
    error_message = "neither postgres nor nautobot may land in pipeline_container_ids"
  }
}

# --- vikunja_container_ids test (issue #141) ---

run "vikunja_tag_filters_correctly" {
  command = plan

  variables {
    containers = {
      "vikunja" = {
        vm_id    = 605010
        hostname = "vikunja"
        vlan     = "apps"
        dhcp     = true
        tags     = ["terraform", "container", "vikunja"]
      }
    }
  }

  assert {
    condition     = local.vikunja_container_ids["vikunja"] == 605010 && length(local.vikunja_container_ids) == 1
    error_message = "vikunja-tagged container must be the sole member of vikunja_container_ids"
  }

  assert {
    condition     = !contains(keys(local.pipeline_container_ids), "vikunja")
    error_message = "vikunja must not land in pipeline_container_ids"
  }
}

# --- authelia_container_ids test ---

run "authelia_tag_filters_correctly" {
  command = plan

  variables {
    containers = {
      "authelia" = {
        vm_id     = 100050
        hostname  = "authelia"
        vlan      = "mgmt"
        ip_config = { ipv4_address = "192.168.5.6/24" }
        tags      = ["terraform", "container", "authelia"]
      }
    }
  }

  assert {
    condition     = local.authelia_container_ids["authelia"] == 100050 && length(local.authelia_container_ids) == 1
    error_message = "authelia-tagged container must be the sole member of authelia_container_ids"
  }

  assert {
    condition     = !contains(keys(local.pipeline_container_ids), "authelia")
    error_message = "authelia must not land in pipeline_container_ids"
  }
}

# A generic 'database'-tagged guest (e.g. mssql) must NOT be pulled into
# postgres_container_ids — only the specific 'postgres' tag opens the 5432 rule.
run "generic_database_tag_not_in_postgres_ids" {
  command = plan

  variables {
    containers = {
      "mssql" = {
        vm_id    = 130
        hostname = "mssql"
        vlan     = "data"
        tags     = ["terraform", "container", "database"]
      }
    }
  }

  assert {
    condition     = length(local.postgres_container_ids) == 0
    error_message = "a container tagged only 'database' (not 'postgres') must NOT be in postgres_container_ids"
  }
}
