# Tests for ansible_inventory output contract
#
# Validates the structure of the ansible_inventory output that downstream
# Ansible repos (ansible-proxmox-apps, ansible-splunk) depend on.
# Any breaking change to this output structure will break downstream inventory loading.
#
# All runs use mock providers (no real infrastructure needed).

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
    name        = "splunk-aio"
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

# --- schema version (issue #134 producer contract) ---

run "ansible_inventory_schema_version" {
  command = plan

  assert {
    condition     = output.ansible_inventory.schema_version == "2.0.0"
    error_message = "ansible_inventory must carry schema_version \"2.0.0\" so the homelab-contracts schema gate can confirm the emitted shape"
  }
}

# --- constants structure tests ---

run "ansible_inventory_nautobot_web_constant" {
  command = plan

  assert {
    condition     = output.ansible_inventory.constants.service_ports.nautobot_web == 8080
    error_message = "constants.service_ports.nautobot_web must be 8080 (Nautobot web UI)"
  }
}

run "ansible_inventory_vikunja_web_constant" {
  command = plan

  assert {
    condition     = output.ansible_inventory.constants.service_ports.vikunja_web == 3456
    error_message = "constants.service_ports.vikunja_web must be 3456 (Vikunja web/API)"
  }
}

run "ansible_inventory_constants_exists" {
  command = plan

  assert {
    condition     = can(output.ansible_inventory.constants)
    error_message = "ansible_inventory must contain 'constants' key"
  }
}

run "ansible_inventory_constants_service_ports_exists" {
  command = plan

  assert {
    condition     = can(output.ansible_inventory.constants.service_ports)
    error_message = "ansible_inventory.constants must contain 'service_ports' key"
  }
}

run "ansible_inventory_constants_syslog_ports_exists" {
  command = plan

  assert {
    condition     = can(output.ansible_inventory.constants.syslog_ports)
    error_message = "ansible_inventory.constants must contain 'syslog_ports' key"
  }
}

run "ansible_inventory_constants_syslog_port_map_exists" {
  command = plan

  assert {
    condition     = can(output.ansible_inventory.constants.syslog_port_map)
    error_message = "ansible_inventory.constants must contain 'syslog_port_map' key"
  }

  assert {
    condition     = output.ansible_inventory.constants.syslog_port_map.unifi.standard == 514
    error_message = "syslog_port_map.unifi.standard must be 514"
  }

  assert {
    condition     = output.ansible_inventory.constants.syslog_port_map.unifi.index == "unifi"
    error_message = "syslog_port_map.unifi.index must be 'unifi'"
  }
}

run "ansible_inventory_constants_netflow_ports_exists" {
  command = plan

  assert {
    condition     = can(output.ansible_inventory.constants.netflow_ports)
    error_message = "ansible_inventory.constants must contain 'netflow_ports' key"
  }
}

run "ansible_inventory_constants_notification_ports_exists" {
  command = plan

  assert {
    condition     = can(output.ansible_inventory.constants.notification_ports)
    error_message = "ansible_inventory.constants must contain 'notification_ports' key"
  }
}

run "ansible_inventory_constants_vector_db_ports_exists" {
  command = plan

  assert {
    condition     = can(output.ansible_inventory.constants.vector_db_ports)
    error_message = "ansible_inventory.constants must contain 'vector_db_ports' key"
  }
}

run "ansible_inventory_constants_memory_ports_exists" {
  command = plan

  assert {
    condition     = can(output.ansible_inventory.constants.memory_ports)
    error_message = "ansible_inventory.constants must contain 'memory_ports' key"
  }
}

run "ansible_inventory_constants_media_ports_exists" {
  command = plan

  assert {
    condition     = can(output.ansible_inventory.constants.media_ports)
    error_message = "ansible_inventory.constants must contain 'media_ports' key for the media stack roles"
  }

  assert {
    condition     = output.ansible_inventory.constants.media_ports.qbittorrent_web == 8080
    error_message = "media_ports.qbittorrent_web must be 8080"
  }

  assert {
    condition     = output.ansible_inventory.constants.media_ports.prowlarr_web == 9696
    error_message = "media_ports.prowlarr_web must be 9696"
  }

  assert {
    condition     = output.ansible_inventory.constants.media_ports.seerr_web == 5055
    error_message = "media_ports.seerr_web must be 5055"
  }
}

# --- key port value tests ---

run "ansible_inventory_splunk_hec_port_value" {
  command = plan

  assert {
    condition     = output.ansible_inventory.constants.service_ports.splunk_hec == 8088
    error_message = "splunk_hec port must be 8088, got ${output.ansible_inventory.constants.service_ports.splunk_hec}"
  }
}

run "ansible_inventory_unifi_syslog_port_value" {
  command = plan

  assert {
    condition     = output.ansible_inventory.constants.syslog_ports.unifi == 1514
    error_message = "unifi syslog port must be 1514, got ${output.ansible_inventory.constants.syslog_ports.unifi}"
  }
}

run "ansible_inventory_unifi_netflow_port_value" {
  command = plan

  assert {
    condition     = output.ansible_inventory.constants.netflow_ports.unifi == 2055
    error_message = "unifi netflow port must be 2055, got ${output.ansible_inventory.constants.netflow_ports.unifi}"
  }
}

# --- top-level structure tests ---

run "ansible_inventory_splunk_vm_exists" {
  command = plan

  assert {
    condition     = can(output.ansible_inventory.splunk_vm)
    error_message = "ansible_inventory must contain 'splunk_vm' key at root level"
  }
}

run "ansible_inventory_containers_exists" {
  command = plan

  assert {
    condition     = can(output.ansible_inventory.containers)
    error_message = "ansible_inventory must contain 'containers' key at root level"
  }
}

# --- splunk_storage: tiered-disk contract (ansible-splunk volume mapping) ---
#
# ansible-splunk maps its hot/warm and cold volume stanzas onto these disks.
# Pin: both the fast and bulk tiers surface with datastore_id + disk_interface +
# size_gb, and it is a top-level key distinct from splunk_vm (which is typed
# against the shared vm schema and must not carry storage fields).
run "ansible_inventory_splunk_storage_contract" {
  command = plan

  assert {
    condition     = can(output.ansible_inventory.splunk_storage)
    error_message = "ansible_inventory must contain 'splunk_storage' key at root level"
  }

  assert {
    condition = (
      output.ansible_inventory.splunk_storage.fast.datastore_id == "fast-splunk" &&
      output.ansible_inventory.splunk_storage.fast.disk_interface == "virtio2" &&
      output.ansible_inventory.splunk_storage.bulk.datastore_id == "bulk-splunk" &&
      output.ansible_inventory.splunk_storage.bulk.disk_interface == "virtio3"
    )
    error_message = "splunk_storage must carry fast-splunk (virtio2) and bulk-splunk (virtio3) tiers with their datastore_id + disk_interface"
  }

  assert {
    condition = (
      output.ansible_inventory.splunk_storage.fast.size_gb == 1024 &&
      output.ansible_inventory.splunk_storage.bulk.size_gb == 2048
    )
    error_message = "splunk_storage tiers must carry size_gb (default 1024 fast / 2048 bulk)"
  }
}

run "ansible_inventory_docker_vms_exists" {
  command = plan

  assert {
    condition     = can(output.ansible_inventory.docker_vms)
    error_message = "ansible_inventory must contain 'docker_vms' key at root level"
  }
}

# --- per-container node placement (example pins a container to proxmox-2) ---

run "ansible_inventory_container_node_override_propagated" {
  command = plan

  variables {
    containers = {
      "download-vpn" = {
        vm_id      = 210
        hostname   = "download-vpn"
        vlan       = "media_svc"
        node_name  = "proxmox-2"
        pool_id    = "media"
        protection = true # exercises the attribute; no longer tied to a policy check
        tags       = ["terraform", "container", "media", "vpn"]
        device_passthrough = [
          { path = "/dev/net/tun", mode = "0666" }
        ]
        mount_points = [
          { volume = "/example-pool/downloads", path = "/mnt/downloads" }
        ]
      }
      "lan-default-node" = {
        vm_id    = 211
        hostname = "lan-default-node"
        vlan     = "apps"
      }
    }
  }

  # node_name set on the container is honored end-to-end in the inventory output.
  assert {
    condition     = output.ansible_inventory.containers["download-vpn"].node == "proxmox-2"
    error_message = "container node_name override must propagate to ansible_inventory.containers[*].node"
  }

  # Containers without node_name fall back to the cluster-wide proxmox_node.
  assert {
    condition     = output.ansible_inventory.containers["lan-default-node"].node == var.proxmox_node
    error_message = "container without node_name must default to var.proxmox_node"
  }
}

# --- ingress: Traefik route table contract ---
#
# `ansible_inventory.ingress` is the SINGLE source the ansible-proxmox-apps
# `traefik` (routers) and `technitium_dns` (aliases) roles consume instead of
# hand-listing hosts/ports. Pin: each fronted service surfaces as {name, ip,
# port} with the IP derived via cidrhost + the port from pipeline_constants, and
# a service whose backend container isn't deployed is skipped (no dangling route).

run "ansible_inventory_ingress_route_table" {
  command = plan

  variables {
    # Only two of the fronted backends are deployed in this fixture; the rest of
    # the ingress_services map must be filtered out.
    containers = {
      "plex" = {
        vm_id    = 210
        hostname = "plex"
        vlan     = "media_svc"
      }
      "seerr" = {
        vm_id    = 211
        hostname = "seerr"
        vlan     = "media_svc"
      }
      # Network-quality monitoring LXC — DNS-first (dhcp) with a 6-digit positional
      # VMID (observability tier 4). No vm_id-derived IP; fronted by FQDN.
      "smokeping" = {
        vm_id         = 990001
        dhcp          = true
        reserved_host = 30
        hostname      = "smokeping"
        vlan          = "mgmt"
        tags          = ["terraform", "container", "monitoring", "docker"]
      }
    }
    domain = "example.com"
  }

  # plex: backend "plex" (192.168.70.210) on media_ports.plex_web (32400).
  assert {
    condition = length([
      for r in output.ansible_inventory.ingress :
      r if r.name == "plex" && r.ip == "192.168.70.210" && r.port == 32400
    ]) == 1
    error_message = "ingress must front plex at 192.168.70.210:32400 (derived IP + constant port)"
  }

  # seerr: backend "seerr" (192.168.70.211) on media_ports.seerr_web (5055).
  assert {
    condition = length([
      for r in output.ansible_inventory.ingress :
      r if r.name == "seerr" && r.ip == "192.168.70.211" && r.port == 5055
    ]) == 1
    error_message = "ingress must front seerr at 192.168.70.211:5055"
  }

  # Every published ingress row carries an explicit sso flag (the forwardAuth
  # gate contract — the ansible consumer treats a missing flag as ungated, so
  # an absent key would silently drop a route out of the SSO gate).
  assert {
    condition = alltrue([
      for r in output.ansible_inventory.ingress : can(r.sso)
    ])
    error_message = "every ingress row must carry an explicit sso flag"
  }

  # Table rows without an explicit opt-out default to gated (sso = true):
  # seerr omits sso in ingress_services; plex opts out (native client auth).
  assert {
    condition = length([
      for r in output.ansible_inventory.ingress :
      r if r.name == "seerr" && r.sso == true
      ]) == 1 && length([
      for r in output.ansible_inventory.ingress :
      r if r.name == "plex" && r.sso == false
    ]) == 1
    error_message = "sso must default true for unmarked rows (seerr) and honor explicit opt-outs (plex)"
  }

  # Services whose backend container is absent are skipped (sonarr not deployed).
  assert {
    condition     = length([for r in output.ansible_inventory.ingress : r if r.name == "sonarr"]) == 0
    error_message = "ingress must skip services whose backend container is not defined"
  }

  # smokeping: DNS-first backend — ingress fronts it by FQDN ({hostname}.{domain}),
  # NOT a vm_id-derived IP, on service_ports.smokeping_web (80).
  assert {
    condition = length([
      for r in output.ansible_inventory.ingress :
      r if r.name == "smokeping" && r.ip == "smokeping.example.com" && r.port == 80
    ]) == 1
    error_message = "ingress must front DHCP guest smokeping at smokeping.example.com:80 (FQDN backend + constant port)"
  }

  # No nodes set in this fixture -> the Proxmox apex pool is empty -> the apex
  # route is omitted entirely (the length(proxmox_ui_backends) > 0 gate).
  assert {
    condition     = length([for r in output.ansible_inventory.ingress : r if r.name == "proxmox"]) == 0
    error_message = "ingress must omit the proxmox apex route when no node is commissioned"
  }
}

# --- ingress: nautobot fronted, postgres never fronted (issue #138) ---
#
# Nautobot's web UI (8080) is a Traefik-fronted route; Postgres is reached only
# in-cluster on 5432 and must NEVER appear in the ingress table.
run "ansible_inventory_ingress_nautobot_not_postgres" {
  command = plan

  variables {
    domain = "example.com"
    containers = {
      "nautobot" = {
        vm_id         = 605000
        hostname      = "nautobot"
        vlan          = "apps"
        dhcp          = true
        reserved_host = 52
        tags          = ["terraform", "container", "nautobot"]
      }
      "postgres" = {
        vm_id         = 303000
        hostname      = "postgres"
        vlan          = "data"
        dhcp          = true
        reserved_host = 51
        tags          = ["terraform", "container", "postgres"]
      }
    }
  }

  # nautobot: DHCP-first backend fronted by FQDN on nautobot_web (8080).
  assert {
    condition = length([
      for r in output.ansible_inventory.ingress :
      r if r.name == "nautobot" && r.ip == "nautobot.example.com" && r.port == 8080
    ]) == 1
    error_message = "ingress must front nautobot at nautobot.example.com:8080 (FQDN backend + nautobot_web constant)"
  }

  # postgres has no ingress_services row -> it must never surface as a route.
  assert {
    condition     = length([for r in output.ansible_inventory.ingress : r if r.name == "postgres"]) == 0
    error_message = "postgres must never appear in the ingress table (in-cluster 5432 only, no Traefik front)"
  }
}

# --- ingress: vikunja fronted (issue #141) ---
run "ansible_inventory_ingress_vikunja_fronted" {
  command = plan

  variables {
    domain = "example.com"
    containers = {
      "vikunja" = {
        vm_id         = 605010
        hostname      = "vikunja"
        vlan          = "apps"
        dhcp          = true
        reserved_host = 53
        tags          = ["terraform", "container", "vikunja"]
      }
    }
  }

  # vikunja: DHCP-first backend fronted by FQDN on vikunja_web (3456).
  assert {
    condition = length([
      for r in output.ansible_inventory.ingress :
      r if r.name == "vikunja" && r.ip == "vikunja.example.com" && r.port == 3456
    ]) == 1
    error_message = "ingress must front vikunja at vikunja.example.com:3456 (FQDN backend + vikunja_web constant)"
  }
}

# --- ingress HA: keepalived VRRP virtual IP contract ---
#
# The keepalived role (ansible-proxmox-apps) + technitium_dns consume ingress_vip
# (the floating IP DNS points every fronted service at) and ingress_hosts (the
# unicast_peer members). Pin: the VIP is derived via cidrhost from the ingress
# containers' own VLAN + the documented reserved octet (2), and every
# ingress-tagged instance is listed. This is what makes ingress node-loss failover
# fully automatic with no hardcoded IP.
run "ansible_inventory_ingress_ha_vip" {
  command = plan

  variables {
    # Two identical Traefik instances on the mgmt VLAN. Instances are pinned to
    # the reserved .7/.8 pair (odd primary, even hot backup) and the floating
    # VIP sits beside them at .9. Octets .1-.19 are reserved estate-wide for
    # network and core services. Every address below is DERIVED via cidrhost
    # from the test CIDR — never a literal host address.
    containers = {
      "traefik-10" = {
        vm_id     = 101
        hostname  = "traefik-10"
        vlan      = "mgmt"
        tags      = ["terraform", "container", "ingress", "traefik"]
        ip_config = { ipv4_address = "${cidrhost("192.168.5.0/24", 7)}/24" }
      }
      "traefik-30" = {
        vm_id     = 107
        hostname  = "traefik-30"
        vlan      = "mgmt"
        tags      = ["terraform", "container", "ingress", "traefik"]
        ip_config = { ipv4_address = "${cidrhost("192.168.5.0/24", 8)}/24" }
      }
    }
  }

  # The VIP is the reserved octet beside the instance pair, derived via cidrhost.
  assert {
    condition     = output.ansible_inventory.ingress_vip == cidrhost("192.168.5.0/24", 9)
    error_message = "ingress_vip must be the reserved VIP octet of the ingress VLAN, derived via cidrhost"
  }

  # Both ingress instances are enrolled as keepalived unicast peers. These must
  # be addresses, never FQDNs — keepalived's unicast_src_ip rejects a name.
  assert {
    condition = length(output.ansible_inventory.ingress_hosts) == 2 && (
      contains(output.ansible_inventory.ingress_hosts, cidrhost("192.168.5.0/24", 7)) &&
      contains(output.ansible_inventory.ingress_hosts, cidrhost("192.168.5.0/24", 8))
    )
    error_message = "ingress_hosts must list every ingress-tagged instance's address (the unicast_peer set)"
  }

  # The VRRP virtual_router_id is surfaced as a constant, not hardcoded downstream.
  assert {
    condition     = output.ansible_inventory.constants.ingress_ports.keepalived_vrid == 51
    error_message = "constants must surface the keepalived VRRP vrid for the ingress HA role"
  }
}

# A single-ingress (or zero) deployment must NOT synthesize a VIP — keepalived
# then no-ops and the deployment stays valid (partial-deploy resilience).
run "ansible_inventory_ingress_ha_single_node_no_vip" {
  command = plan

  variables {
    containers = {
      "traefik" = {
        vm_id    = 101
        hostname = "traefik"
        vlan     = "mgmt"
        tags     = ["terraform", "container", "ingress", "traefik"]
      }
    }
  }

  assert {
    condition     = output.ansible_inventory.ingress_vip == "" && length(output.ansible_inventory.ingress_hosts) == 1
    error_message = "a single ingress instance must NOT synthesize a VIP (it would never bind, black-holing DNS) — DNS must fall back to the single host's IP"
  }
}

# Proxmox cluster UI apex: the subdomain apex load-balanced across the
# commissioned node role FQDNs (https://<role>.<domain>:8006). Pins the
# multi-backend + apex contract the ansible-proxmox-apps traefik role consumes.
run "ansible_inventory_ingress_apex_proxmox" {
  command = plan

  variables {
    domain = "example.com"
    nodes = {
      # role is the resolvable FQDN label; proxmox3 is un-commissioned and must
      # drop out of the load-balanced pool. Sample values only.
      proxmox1 = { role = "proxmox1" }
      proxmox2 = { role = "proxmox2" }
      proxmox3 = { role = "proxmox3", commissioned = false }
    }
  }

  # The apex entry fronts the subdomain apex with a multi-backend pool built from
  # the commissioned node role FQDNs (proxmox1/proxmox2), https + skip-verify for
  # the self-signed node certs, and sticky + health-check flags for the LB.
  # proxmox3 (un-commissioned) is excluded. Apex-only fields are read via try()
  # because the ingress tuple is heterogeneous (container/splunk rows lack them).
  assert {
    condition = length([
      for r in output.ansible_inventory.ingress : r
      if r.name == "proxmox"
      && try(r.apex, false)
      && try(r.backends, []) == ["proxmox1.example.com", "proxmox2.example.com"]
      && try(r.port, 0) == 8006
      && try(r.scheme, "") == "https"
      && try(r.insecure_tls, false)
      && try(r.sticky, false)
      && try(r.health_check, false)
    ]) == 1
    error_message = "ingress must front the Proxmox UI apex (the subdomain apex) with an https sticky health-checked pool over the commissioned node role FQDNs, excluding un-commissioned nodes"
  }
}

run "ansible_inventory_ingress_openbao_ha_pool" {
  command = plan

  variables {
    domain = "example.com"
    containers = {
      "openbao-31" = {
        vm_id     = 110031
        node_name = "proxmox-5"
        hostname  = "openbao-31"
        vlan      = "mgmt"
        ip_config = { ipv4_address = "192.168.5.31/24" }
        tags      = ["terraform", "container", "openbao", "secrets", "infrastructure"]
      }
      "openbao-10" = {
        vm_id     = 110010
        node_name = "proxmox-1"
        hostname  = "openbao-10"
        vlan      = "mgmt"
        ip_config = { ipv4_address = "192.168.5.10/24" }
        tags      = ["terraform", "container", "openbao", "secrets", "infrastructure"]
      }
      "openbao-21" = {
        vm_id     = 110021
        node_name = "proxmox-3"
        hostname  = "openbao-21"
        vlan      = "mgmt"
        ip_config = { ipv4_address = "192.168.5.21/24" }
        tags      = ["terraform", "container", "openbao", "secrets", "infrastructure"]
      }
      "openbao-30" = {
        vm_id     = 110030
        node_name = "proxmox-4"
        hostname  = "openbao-30"
        vlan      = "mgmt"
        ip_config = { ipv4_address = "192.168.5.30/24" }
        tags      = ["terraform", "container", "openbao", "secrets", "infrastructure"]
      }
      "openbao-20" = {
        vm_id     = 110020
        node_name = "proxmox-2"
        hostname  = "openbao-20"
        vlan      = "mgmt"
        ip_config = { ipv4_address = "192.168.5.20/24" }
        tags      = ["terraform", "container", "openbao", "secrets", "infrastructure"]
      }
    }
  }

  assert {
    condition = length([
      for r in output.ansible_inventory.ingress : r
      if r.name == "openbao"
      && try(r.backends, []) == [
        "openbao-10.example.com",
        "openbao-20.example.com",
        "openbao-21.example.com",
        "openbao-30.example.com",
        "openbao-31.example.com",
      ]
      && try(r.port, 0) == 8200
      && !try(r.sticky, true)
      && try(r.health_check, false)
      && try(r.health_check_path, "") == "/v1/sys/health"
    ]) == 1
    error_message = "ingress must front OpenBao with a sorted, non-sticky, active-only 5-backend HA pool addressed by <hostname>.<domain> FQDN (never a bare/derived IP, which goes stale the moment a peer is rebuilt elsewhere) and a health check of /v1/sys/health with no standbyok — routes to the Raft leader; no sticky cookie, or clients get pinned to an evicted backend across elections"
  }
}

# --- host_services structure tests ---

run "ansible_inventory_host_services_exists" {
  command = plan

  assert {
    condition     = can(output.ansible_inventory.host_services)
    error_message = "ansible_inventory must contain 'host_services' key at root level"
  }
}

run "ansible_inventory_host_services_default_no_nas" {
  command = plan

  assert {
    condition     = output.ansible_inventory.host_services.nas == null
    error_message = "ansible_inventory.host_services.nas must be null when no host_services var is set"
  }
}

# --- domain propagation tests ---

run "ansible_inventory_domain_field_exists" {
  command = plan

  assert {
    condition     = can(output.ansible_inventory.domain)
    error_message = "ansible_inventory must contain 'domain' key for downstream FQDN configuration"
  }
}

# --- untagged-native vlan key + static IP override ---
#
# A vlan key present in network_cidrs but ABSENT from vlan_ids yields an untagged NIC
# (native VLAN). A container MAY also pin a static ipv4_address overriding the
# vm_id-derived address (e.g. a fixed DNS server at .10). Both feed the inventory.

run "ansible_inventory_untagged_native_and_static_ip" {
  command = plan

  variables {
    # Add an untagged native-Management key (intentionally NOT in vlan_ids).
    network_cidrs = merge(
      { for name, id in var.vlan_ids : name => "192.168.${id}.0/24" },
      { mgmt_native = "192.168.5.0/24" }
    )
    containers = {
      # On an untagged key; planning at all proves lookup(var.vlan_ids, vlan, null)
      # avoids the missing-key error. IP derives from vm_id.
      "dns-derived" = {
        vm_id    = 110
        hostname = "dns-derived"
        vlan     = "mgmt_native"
      }
      # Static ipv4_address must override the vm_id-derived address.
      "dns-static" = {
        vm_id     = 111
        hostname  = "dns-static"
        vlan      = "mgmt_native"
        ip_config = { ipv4_address = "192.168.5.10/24" }
      }
    }
  }

  assert {
    condition     = output.ansible_inventory.containers["dns-derived"].ip == "192.168.5.110"
    error_message = "container on a vlan key absent from vlan_ids must plan (untagged) and derive ip from vm_id"
  }

  assert {
    condition     = output.ansible_inventory.containers["dns-static"].ip == "192.168.5.10"
    error_message = "ip_config.ipv4_address must override the vm_id-derived address in the inventory"
  }
}

run "ansible_inventory_domain_default_empty" {
  command = plan

  assert {
    condition     = output.ansible_inventory.domain == ""
    error_message = "ansible_inventory.domain should be empty string when var.domain is not set"
  }
}

run "ansible_inventory_domain_propagated" {
  command = plan

  variables {
    domain = "example.com"
  }

  assert {
    condition     = output.ansible_inventory.domain == "example.com"
    error_message = "ansible_inventory.domain must propagate var.domain, got '${output.ansible_inventory.domain}'"
  }
}

run "ansible_inventory_host_services_nas_propagated" {
  command = plan

  variables {
    host_services = {
      nas = {
        zfs_dataset    = "rpool/data/nas"
        zfs_quota      = "1T"
        mount_point    = "/mnt/nas"
        smb_share_name = "nas"
        directories    = ["huggingface/hub", "ollama/models", "media", "backups"]
        group_name     = "nas"
        managed_users = [
          {
            name                = "homeassistant"
            unix_groups         = ["nas"]
            shell               = "/usr/sbin/nologin"
            create_home         = false
            password_secret_env = "NAS_HOMEASSISTANT_SMB_PASSWORD"
          }
        ]
        shares = [
          {
            name           = "nas"
            path           = "/mnt/nas"
            valid_users    = "@nas"
            browsable      = true
            read_only      = false
            force_group    = "nas"
            create_mask    = "0664"
            directory_mask = "0775"
            comment        = "Primary NAS root share"
          },
          {
            name           = "ha-backups"
            path           = "/mnt/nas/backups"
            valid_users    = "homeassistant"
            browsable      = true
            read_only      = false
            force_group    = "nas"
            create_mask    = "0664"
            directory_mask = "0775"
            comment        = "Home Assistant backup storage"
            time_machine   = true
          }
        ]
      }
    }
  }

  assert {
    condition     = output.ansible_inventory.host_services.nas.zfs_dataset == "rpool/data/nas"
    error_message = "host_services.nas.zfs_dataset must propagate to ansible_inventory output"
  }

  assert {
    condition     = output.ansible_inventory.host_services.nas.mount_point == "/mnt/nas"
    error_message = "host_services.nas.mount_point must propagate to ansible_inventory output"
  }

  assert {
    condition     = output.ansible_inventory.host_services.nas.group_name == "nas"
    error_message = "host_services.nas.group_name must propagate to ansible_inventory output"
  }

  assert {
    condition     = output.ansible_inventory.host_services.nas.managed_users[0].password_secret_env == "NAS_HOMEASSISTANT_SMB_PASSWORD"
    error_message = "host_services.nas.managed_users must propagate to ansible_inventory output"
  }

  assert {
    condition     = output.ansible_inventory.host_services.nas.shares[1].name == "ha-backups"
    error_message = "host_services.nas.shares must propagate to ansible_inventory output"
  }

  assert {
    condition     = output.ansible_inventory.host_services.nas.shares[1].time_machine == true
    error_message = "host_services.nas.shares time_machine must propagate to ansible_inventory output"
  }
}

# --- multi-node: nodes + node_storage contract ---

run "ansible_inventory_nodes_exists" {
  command = plan

  assert {
    condition     = can(output.ansible_inventory.nodes)
    error_message = "ansible_inventory must contain 'nodes' key for downstream host targeting"
  }
}

run "ansible_inventory_node_storage_exists" {
  command = plan

  assert {
    condition     = can(output.ansible_inventory.node_storage)
    error_message = "ansible_inventory must contain 'node_storage' key for ansible-proxmox ZFS provisioning"
  }
}

run "ansible_inventory_nodes_commissioned_propagated" {
  command = plan

  variables {
    nodes = {
      proxmox-1 = { role = "node-1" }
      proxmox-3 = { role = "node-3", commissioned = false }
    }
  }

  assert {
    condition     = output.ansible_inventory.nodes["proxmox-1"].commissioned == true
    error_message = "nodes commissioned must default to true"
  }

  assert {
    condition     = output.ansible_inventory.nodes["proxmox-3"].commissioned == false
    error_message = "nodes commissioned=false must propagate (gates apply on un-commissioned nodes)"
  }
}

run "ansible_inventory_node_storage_propagated" {
  command = plan

  variables {
    node_storage = {
      proxmox-2 = {
        pools = {
          example-pool = {
            raid     = "raidz1"
            datasets = { backups = { quota = "1T", properties = { recordsize = "1M", compression = "zstd" } } }
          }
        }
      }
    }
  }

  assert {
    condition     = output.ansible_inventory.node_storage["proxmox-2"].pools["example-pool"].datasets["backups"].quota == "1T"
    error_message = "node_storage pool/dataset/quota must propagate to ansible_inventory for ansible-proxmox"
  }

  assert {
    condition     = output.ansible_inventory.node_storage["proxmox-2"].pools["example-pool"].datasets["backups"].properties["recordsize"] == "1M"
    error_message = "node_storage dataset properties must propagate to ansible_inventory for ansible-proxmox"
  }

  assert {
    condition     = output.ansible_inventory.node_storage["proxmox-2"].pools["example-pool"].register == true
    error_message = "node_storage pool register must default to true"
  }

  assert {
    condition     = output.ansible_inventory.node_storage["proxmox-2"].pools["example-pool"].protected == true
    error_message = "node_storage pool protected must default to true (storage-safety)"
  }
}

# --- multi-node: per-resource node placement ---

run "vm_node_placement_defaults_to_primary" {
  command = plan

  variables {
    vms = {
      placement = {
        vm_id = 210
        name  = "placement-default"
        vlan  = "apps"
      }
    }
  }

  assert {
    condition     = output.ansible_inventory.vms["placement"].node == "proxmox-1"
    error_message = "a VM without node_name must default to the primary node (var.proxmox_node)"
  }
}

run "vm_node_placement_override" {
  command = plan

  variables {
    vms = {
      placement = {
        vm_id     = 211
        name      = "placement-proxmox-2"
        vlan      = "apps"
        node_name = "proxmox-2"
      }
    }
  }

  assert {
    condition     = output.ansible_inventory.vms["placement"].node == "proxmox-2"
    error_message = "a VM with node_name set must be placed on that node"
  }
}

# An ISO-appliance VM (cdrom_file_id, an extra datastore disk, and no
# clone_template) must plan — this is the shape the PBS backup appliance uses.
run "vm_iso_appliance_plans" {
  command = plan

  variables {
    vms = {
      pbs = {
        vm_id            = 240
        name             = "pbs"
        vlan             = "compute"
        node_name        = "proxmox-2"
        cdrom_file_id    = "local:iso/proxmox-backup-server.iso"
        boot_disk        = { datastore_id = "local-zfs", size = 32 }
        additional_disks = [{ interface = "scsi1", datastore_id = "local-zfs", size = 1024 }]
        protection       = true
        tags             = ["terraform", "backup", "pbs"]
      }
    }
  }

  assert {
    condition     = output.ansible_inventory.vms["pbs"].node == "proxmox-2"
    error_message = "ISO-appliance VM (cdrom_file_id, extra disk, no clone_template) must plan and land on its node"
  }
}

# --- base LXC template ---
#
# ansible-proxmox ensures this exact filename on every node's local storage
# (pve_repositories role). It used to re-declare the value in its own defaults,
# kept aligned with this module by a code comment; publishing it here makes
# deployment.json the single place the base image is named.

run "ansible_inventory_ct_template_published" {
  command = plan

  assert {
    condition     = output.ansible_inventory.ct_template != ""
    error_message = "ansible_inventory must publish a non-empty ct_template — ansible-proxmox downloads this filename onto each node and container creation references it by name"
  }
}

run "ansible_inventory_ct_template_reflects_input" {
  command = plan

  variables {
    proxmox_ct_template_debian = "debian-13-standard_13.6-1_amd64.tar.zst"
  }

  assert {
    condition     = output.ansible_inventory.ct_template == "debian-13-standard_13.6-1_amd64.tar.zst"
    error_message = "ct_template must carry the configured template through to the inventory, so bumping the base image in deployment.json reaches ansible-proxmox"
  }
}
