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
    condition     = output.ansible_inventory.schema_version == "2.1.0"
    error_message = "ansible_inventory must carry schema_version \"2.1.0\" so the homelab-contracts schema gate can confirm the emitted shape"
  }
}

# --- desired-state fingerprint ---
#
# The staleness check downstream is only as good as this key's presence: a
# consumer that cannot find it cannot tell a current artifact from one rendered
# before the last desired-state edit, and silently falls back to assuming it is
# current. Assert the key exists and carries the module inputs verbatim, so
# dropping or renaming it fails here rather than degrading the detector in
# place.

run "ansible_inventory_desired_state_fingerprint" {
  command = plan

  variables {
    desired_state_etag = "d41d8cd98f00b204e9800998ecf8427e"
  }

  assert {
    condition     = output.ansible_inventory.desired_state.etag == "d41d8cd98f00b204e9800998ecf8427e"
    error_message = "ansible_inventory.desired_state.etag must carry the desired-state object's ETag — it is what tells a consumer whether an apply is owed before it converges"
  }
}

run "ansible_inventory_desired_state_defaults_empty" {
  command = plan

  assert {
    condition     = output.ansible_inventory.desired_state.etag == ""
    error_message = "desired_state.etag must default to empty, so a store that returns no ETag disables the downstream check instead of failing every converge"
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

run "ansible_inventory_syslog_families_never_widen_the_os_catch_all" {
  command = plan

  # `os` is already the largest index while carrying three unrelated OS families
  # (linux, windows, macos). Every family added from here routes somewhere
  # narrower, so this asserts the exact set allowed to land there rather than
  # asserting the new family alone — a future family quietly defaulting to `os`
  # is the failure worth catching, and only a whitelist catches it.
  assert {
    condition = length([
      for name, fam in output.ansible_inventory.constants.syslog_port_map :
      name if fam.index == "os" && !contains(["linux", "windows", "macos"], name)
    ]) == 0
    error_message = "A syslog family outside {linux,windows,macos} routes to the 'os' catch-all. Give it a narrower index — os is already the largest and carries three unrelated families."
  }

  # Ports are the routing key, so a collision silently sends one family's data
  # to another's index. Cheap to assert, effectively impossible to spot by eye.
  assert {
    condition     = length(values(output.ansible_inventory.constants.syslog_port_map)[*].standard) == length(distinct(values(output.ansible_inventory.constants.syslog_port_map)[*].standard))
    error_message = "Two syslog families share a 'standard' port; each family needs its own HAProxy frontend port."
  }

  assert {
    condition     = length(values(output.ansible_inventory.constants.syslog_port_map)[*].high) == length(distinct(values(output.ansible_inventory.constants.syslog_port_map)[*].high))
    error_message = "Two syslog families share a 'high' port; each family needs its own Cribl Edge backend port."
  }
}

run "ansible_inventory_pve_health_family_published" {
  command = plan

  # The host-config repo's telemetry role forwards to this family by port and the
  # Cribl pipeline stamps the index from it, so an absent or renamed entry sends
  # hypervisor health data nowhere (or into the wrong index) with no error.
  assert {
    condition     = try(output.ansible_inventory.constants.syslog_port_map.pve_health.standard, 0) == 524
    error_message = "syslog_port_map.pve_health.standard must be 524 — the telemetry role's rsyslog forward targets this port."
  }

  assert {
    condition     = try(output.ansible_inventory.constants.syslog_port_map.pve_health.index, "") == "os_proxmox"
    error_message = "syslog_port_map.pve_health.index must be 'os_proxmox' — hypervisor-scoped, and deliberately not the 'os' catch-all."
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
        node_name  = "proxmox-1"
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
        vm_id     = 211
        node_name = "proxmox-1"
        hostname  = "lan-default-node"
        vlan      = "apps"
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
        vm_id     = 210
        node_name = "proxmox-1"
        hostname  = "plex"
        vlan      = "media_svc"
      }
      "seerr" = {
        vm_id     = 211
        node_name = "proxmox-1"
        hostname  = "seerr"
        vlan      = "media_svc"
      }
      # Network-quality monitoring LXC — DNS-first (dhcp) with a 6-digit positional
      # VMID (observability tier 4). No vm_id-derived IP; fronted by FQDN.
      "smokeping" = {
        vm_id     = 990001
        node_name = "proxmox-1"
        dhcp      = true
        hostname  = "smokeping"
        vlan      = "mgmt"
        tags      = ["terraform", "container", "monitoring", "docker"]
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

  # Every published ingress row also carries a non-empty group. The estate
  # dashboards (Homarr, Homepage, Glance) are all rendered from this one list,
  # so a missing group silently drops a service off every board at once — the
  # same class of failure the sso assertion above guards.
  assert {
    condition = alltrue([
      for r in output.ansible_inventory.ingress : can(r.group) && r.group != ""
    ])
    error_message = "every ingress row must carry a non-empty group"
  }

  # A container-backed route inherits its backend's VLAN rather than falling
  # through to the "other" default. seerr is on the media_svc VLAN in the test
  # fixture; if this ever reads "other", the VLAN inheritance has broken and
  # every board would collapse into one undifferentiated group while still
  # passing the presence assertion above.
  assert {
    condition = length([
      for r in output.ansible_inventory.ingress :
      r if r.name == "seerr" && r.group == "media_svc"
    ]) == 1
    error_message = "seerr's ingress group must be inherited from its backend container's VLAN (media_svc)"
  }

  # A route with NO backend container (the Splunk VM here; pool routes behave the
  # same) takes its group from the map in locals-ingress-groups.tf. Without this
  # the presence assertion above still passes on the "other" fallback, so every
  # pool and VM route would silently collapse into one catch-all group.
  assert {
    condition = length([
      for r in output.ansible_inventory.ingress :
      r if r.name == "splunk" && r.group == "siem"
    ]) == 1
    error_message = "a backend-less route must take its group from ingress_route_groups (splunk => siem), not the \"other\" fallback"
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
        vm_id     = 605000
        node_name = "proxmox-1"
        hostname  = "nautobot"
        vlan      = "apps"
        dhcp      = true
        tags      = ["terraform", "container", "nautobot"]
      }
      "postgres" = {
        vm_id     = 303000
        node_name = "proxmox-1"
        hostname  = "postgres"
        vlan      = "data"
        dhcp      = true
        tags      = ["terraform", "container", "postgres"]
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
        vm_id     = 605010
        node_name = "proxmox-1"
        hostname  = "vikunja"
        vlan      = "apps"
        dhcp      = true
        tags      = ["terraform", "container", "vikunja"]
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
        node_name = "proxmox-1"
        hostname  = "traefik-10"
        vlan      = "mgmt"
        tags      = ["terraform", "container", "ingress", "traefik"]
        ip_config = { ipv4_address = "${cidrhost("192.168.5.0/24", 7)}/24" }
      }
      "traefik-30" = {
        vm_id     = 107
        node_name = "proxmox-1"
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
        vm_id     = 101
        node_name = "proxmox-1"
        hostname  = "traefik"
        vlan      = "mgmt"
        tags      = ["terraform", "container", "ingress", "traefik"]
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
        node_name = "proxmox-1"
        node_name = "proxmox-5"
        hostname  = "openbao-31"
        vlan      = "mgmt"
        ip_config = { ipv4_address = "192.168.5.31/24" }
        tags      = ["terraform", "container", "openbao", "secrets", "infrastructure"]
      }
      "openbao-10" = {
        vm_id     = 110010
        node_name = "proxmox-1"
        node_name = "proxmox-1"
        hostname  = "openbao-10"
        vlan      = "mgmt"
        ip_config = { ipv4_address = "192.168.5.10/24" }
        tags      = ["terraform", "container", "openbao", "secrets", "infrastructure"]
      }
      "openbao-21" = {
        vm_id     = 110021
        node_name = "proxmox-1"
        node_name = "proxmox-3"
        hostname  = "openbao-21"
        vlan      = "mgmt"
        ip_config = { ipv4_address = "192.168.5.21/24" }
        tags      = ["terraform", "container", "openbao", "secrets", "infrastructure"]
      }
      "openbao-30" = {
        vm_id     = 110030
        node_name = "proxmox-1"
        node_name = "proxmox-4"
        hostname  = "openbao-30"
        vlan      = "mgmt"
        ip_config = { ipv4_address = "192.168.5.30/24" }
        tags      = ["terraform", "container", "openbao", "secrets", "infrastructure"]
      }
      "openbao-20" = {
        vm_id     = 110020
        node_name = "proxmox-1"
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
        vm_id     = 110
        node_name = "proxmox-1"
        hostname  = "dns-derived"
        vlan      = "mgmt_native"
      }
      # Static ipv4_address must override the vm_id-derived address.
      "dns-static" = {
        vm_id     = 111
        node_name = "proxmox-1"
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

# The node object type strips any attribute it does not declare, and it does so
# silently — an undeclared key reaches neither the output nor an error. The
# consumer of this field matches its records by name alone, so losing it makes
# that consumer create a duplicate record rather than match the existing one.
# Assert it survives the type, and that omitting it stays null rather than
# inventing a value.
run "ansible_inventory_nodes_device_name_propagated" {
  command = plan

  variables {
    nodes = {
      proxmox-1 = { role = "node-1", nautobot_device_name = "renamed-1" }
      proxmox-3 = { role = "node-3" }
    }
  }

  assert {
    condition     = output.ansible_inventory.nodes["proxmox-1"].nautobot_device_name == "renamed-1"
    error_message = "nautobot_device_name must survive the node object type and reach ansible_inventory"
  }

  assert {
    condition     = output.ansible_inventory.nodes["proxmox-3"].nautobot_device_name == null
    error_message = "an unset nautobot_device_name must publish as null, so a consumer can fall back to the key"
  }
}

# The dataset object type strips any attribute it does not declare, silently:
# an undeclared key reaches neither the output nor an error. `sparse` was lost
# exactly this way — it passed the desired-state JSON schema, survived an apply,
# and never reached Ansible, so the reconcile task on the other side skipped and
# the declaration read back as correct while every disk was still created thick.
run "ansible_inventory_node_storage_sparse_propagated" {
  command = plan

  variables {
    node_storage = {
      proxmox-2 = {
        pools = {
          example-pool = {
            raid   = "raidz1"
            sparse = true
            datasets = {
              thin  = { quota = "500G", pvesm_id = "thin-store", sparse = true }
              thick = { quota = "500G", pvesm_id = "thick-store" }
            }
          }
        }
      }
    }
  }

  assert {
    condition     = output.ansible_inventory.node_storage["proxmox-2"].pools["example-pool"].datasets["thin"].sparse == true
    error_message = "a declared sparse must survive the dataset object type and reach ansible_inventory"
  }

  # A pool registered directly as PVE storage takes the same flag. It was added
  # one release after the dataset field and is the same silent-strip risk.
  assert {
    condition     = output.ansible_inventory.node_storage["proxmox-2"].pools["example-pool"].sparse == true
    error_message = "a declared sparse must survive the POOL object type and reach ansible_inventory"
  }

  # False, not null: the consumer compares it against what Proxmox reports, and
  # Proxmox reports absent-means-off. A null here would make that comparison
  # ambiguous rather than simply "not thin".
  assert {
    condition     = output.ansible_inventory.node_storage["proxmox-2"].pools["example-pool"].datasets["thick"].sparse == false
    error_message = "an unset sparse must publish as false, matching what Proxmox reports for a thick storage"
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

  # False, not null — the consumer compares it against what Proxmox reports, and
  # Proxmox omits the key entirely when sparse is off.
  assert {
    condition     = output.ansible_inventory.node_storage["proxmox-2"].pools["example-pool"].sparse == false
    error_message = "an unset pool sparse must publish as false, matching what Proxmox reports for a thick storage"
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
        vm_id     = 210
        node_name = "proxmox-1"
        name      = "placement-default"
        vlan      = "apps"
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
        node_name = "proxmox-1"
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
        node_name        = "proxmox-1"
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

# The stack's own object type is where `on_boot` went missing: `modules/
# proxmox-vm` declared it, the resource wired it, but `var.vms` here did not
# list it, so an object type constraint dropped it before it ever reached the
# module. Every guest was pinned to the default. Nothing failed — the wiring
# used `try()`, which turns a missing attribute into a silent fallback.
#
# The passthrough test in modules/proxmox-vm cannot catch this: it feeds that
# module directly and never crosses this type boundary. So assert here that the
# fields survive the stack's own type. Referencing an attribute the type does
# not declare fails the run, which is exactly the regression.
run "startup_fields_survive_the_stack_object_type" {
  command = plan

  variables {
    vms = {
      manual = {
        vm_id     = 212
        node_name = "proxmox-1"
        name      = "manual-start-only"
        vlan      = "apps"
        on_boot   = false
        started   = false
      }
    }
  }

  # Assert through the published output, NOT through `var.vms`. A test's own
  # `variables` block bypasses the variable's type constraint, so an assertion
  # reading `var.vms["manual"].on_boot` passes even with `on_boot` deleted from
  # the type — verified by deleting it. That reads as coverage and is none.
  assert {
    condition     = output.ansible_inventory.vms["manual"].on_boot == false
    error_message = "on_boot did not survive the stack's vms object type — deployment.json could ask a guest not to start with its node and be silently ignored."
  }

  assert {
    condition     = output.ansible_inventory.vms["manual"].started == false
    error_message = "started did not survive the stack's vms object type — deployment.json could ask for a manually-started guest and terraform would power it on anyway."
  }
}

# The VDI split-tunnel routes are (destination, gateway) pairs assembled from two
# separate places in this file, and BOTH halves are useless alone. Assert them
# through the output for the same reason as the startup fields above: a test's
# own `variables` block bypasses the object type, so reading `var.vms[...]`
# would pass with the attribute deleted from the type.
run "vdi_route_inputs_reach_the_inventory" {
  command = plan

  variables {
    vdi_preserved_vlans = ["apps", "siem"]

    vms = {
      desktop = {
        vm_id     = 213
        node_name = "proxmox-1"
        name      = "vdi-desktop"
        vlan      = "apps"
        tags      = ["vdi"]
      }
    }
  }

  # The gateway half. cidrhost(<apps cidr>, 1) — derived, never written down, so
  # the assertion derives it the same way rather than pinning an octet.
  assert {
    condition     = output.ansible_inventory.vms["desktop"].gateway == cidrhost(var.network_cidrs["apps"], 1)
    error_message = "A VM's gateway did not reach the inventory — a VDI guest cannot discover it once a VPN client owns the default route, so the persistent LAN routes cannot be built."
  }

  # The destination half, in the order the vlan keys were listed.
  assert {
    condition = output.ansible_inventory.vdi_preserved_cidrs == [
      var.network_cidrs["apps"], var.network_cidrs["siem"],
    ]
    error_message = "vdi_preserved_vlans did not resolve into vdi_preserved_cidrs — the VDI role would receive no destinations and silently add no routes."
  }
}

# Negative control. Without this, the run above still passes if the feature were
# hard-wired on, which would push routes at every estate that never asked for
# them. Empty is the default and must stay a real no-op.
run "vdi_routes_stay_empty_when_no_vlans_are_listed" {
  command = plan

  assert {
    condition     = length(output.ansible_inventory.vdi_preserved_cidrs) == 0
    error_message = "vdi_preserved_cidrs is non-empty with vdi_preserved_vlans unset — the VDI routing standard must be opt-in."
  }
}

# Regression: the published gateway was originally the cloud-init one, which is
# null on a DHCP-first guest. The estate is DHCP-first by design, so that guard
# rejected every real VDI guest while every test passed — none of them declared
# dhcp. A VDI guest addressed by lease must still publish its VLAN's gateway.
run "a_dhcp_first_vdi_guest_still_publishes_its_gateway" {
  command = plan

  variables {
    vdi_preserved_vlans = ["apps"]

    vms = {
      leased = {
        vm_id     = 995119
        node_name = "proxmox-1"
        name      = "vdi-leased"
        vlan      = "apps"
        dhcp      = true
        tags      = ["vdi"]
      }
    }
  }

  assert {
    condition     = output.ansible_inventory.vms["leased"].gateway == cidrhost(var.network_cidrs["apps"], 1)
    error_message = "A DHCP-first VDI guest published no gateway — its split-tunnel routes cannot be built, and DHCP-first is the estate default rather than the exception."
  }
}

# Proxmox validates a downloaded file's extension against the content type it is
# filed under, and separately refuses an iso-type volume as a disk import source.
# Getting these out of step aborted two applies before the inventory published:
# .qcow2 under `iso` failed at download, .img under `iso` failed one step later
# at disk creation. `import` is the content type that accepts a disk image, and
# UPLOAD_IMPORT_EXT_RE_1 is what it accepts.
run "the_cloud_image_filename_matches_the_import_content_type" {
  command = plan

  assert {
    condition     = can(regex("(?i)\\.(qcow2|raw|vmdk|ova)$", var.debian_cloudimg_file_name))
    error_message = "debian_cloudimg_file_name must end in .qcow2, .raw, .vmdk or .ova — those are the extensions Proxmox accepts for `import` content, and a mismatch aborts the apply before the inventory is published."
  }
}

# --- host_services removal ---

# The former global host_services.nas had no node selector, so every node built
# an identical NAS. Shares now live on the dataset they serve, in node_storage.
# Asserted rather than merely deleted: a consumer still reading host_services
# would otherwise fail at converge time, not here.
run "ansible_inventory_has_no_host_services" {
  command = plan

  assert {
    condition     = !can(output.ansible_inventory.host_services)
    error_message = "ansible_inventory must no longer expose 'host_services'; shares are declared per dataset in node_storage"
  }
}


# --- guest sizing, for Nautobot's VirtualMachine fields ---

# Nautobot models vcpus/memory/disk natively and every guest read null, because
# nothing carried the declared sizing downstream: the desired state has it, the
# inventory did not, so the seed bundle could not either.
#
# Asserted as a CONTRACT rather than trusted: these are plain attribute reads
# (not try()), so an undeclared attribute breaks the plan instead of publishing
# a null that looks like "this guest has no sizing".
run "ansible_inventory_publishes_guest_sizing" {
  command = plan

  # This run needs its OWN containers: the file-level fixture declares none, and
  # `alltrue([])` is TRUE — so every assertion below would pass vacuously against
  # an empty map. Caught by mutation: rescaling memory x1024 left the suite green
  # until this fixture existed.
  variables {
    containers = {
      "sizing-probe" = {
        node_name        = "proxmox-1"
        vm_id            = 199
        hostname         = "sizing-probe"
        vlan             = "dns"
        cpu_cores        = 4
        memory_dedicated = 8192
        root_disk        = { size = 24 }
      }
    }
    # A VM too. Same reason the containers fixture exists: `alltrue([])` is TRUE,
    # so the VM assertions below were vacuous until something was here. This was
    # caught by mutation twice -- fixed for containers, then reintroduced for
    # vms, and only the mutation showed it.
    vms = {
      "sizing-probe-vm" = {
        node_name        = "proxmox-1"
        vm_id            = 198
        name             = "sizing-probe-vm"
        vlan             = "apps"
        cpu_cores        = 8
        memory_dedicated = 16384
        boot_disk        = { size = 64 }
      }
    }
  }

  # The fixture must actually reach the output, or the checks below are vacuous
  # again for a different reason.
  assert {
    condition     = length(output.ansible_inventory.containers) > 0 && length(output.ansible_inventory.vms) > 0
    error_message = "containers or vms published empty, so the sizing assertions below would pass vacuously against an empty map"
  }

  assert {
    condition     = alltrue([for k, c in output.ansible_inventory.containers : can(c.cpu_cores) && can(c.memory_mb) && can(c.disk_gb)])
    error_message = "every published container must carry cpu_cores, memory_mb and disk_gb; a missing field leaves Nautobot's VirtualMachine sizing null"
  }

  # Zero or null would populate Nautobot with confident nonsense, which is worse
  # than an empty field: an empty field is honestly unknown, a 0 reads as real.
  assert {
    condition     = alltrue([for k, c in output.ansible_inventory.containers : c.cpu_cores > 0 && c.memory_mb > 0 && c.disk_gb > 0])
    error_message = "published sizing must be positive; a 0 or null would record a guest as having no CPU, memory or disk"
  }

  # Units are the guest's own and match Nautobot's (memory MB, disk GB) so they
  # map across without conversion. This pins the magnitude: a value rescaled to
  # bytes or GB-as-MB still passes the > 0 check above while being wrong by
  # three orders of magnitude.
  assert {
    condition     = alltrue([for k, c in output.ansible_inventory.containers : c.memory_mb >= 64 && c.memory_mb <= 65536])
    error_message = "memory_mb is outside the declared MB range, which means the unit was rescaled somewhere"
  }

  # VMs too, not just containers. Publishing sizing for containers only left the
  # actual VMs -- the guests the Nautobot field name refers to -- reading null,
  # which looked like success because most guests here ARE containers.
  assert {
    condition     = alltrue([for k, v in output.ansible_inventory.vms : can(v.cpu_cores) && can(v.memory_mb) && can(v.disk_gb)])
    error_message = "every published VM must carry cpu_cores, memory_mb and disk_gb; containers alone is not the field Nautobot means by VM sizing"
  }

  assert {
    condition     = alltrue([for k, v in output.ansible_inventory.vms : v.cpu_cores > 0 && v.memory_mb > 0 && v.disk_gb > 0])
    error_message = "published VM sizing must be positive; a 0 records a guest as having no CPU, memory or disk"
  }

  # EVERY guest-publishing slice, not one at a time. Sizing was added to
  # containers, then vms, then docker_vms and splunk_vm -- three rounds, because
  # each fix addressed the instance instead of the class, and each time the
  # count went UP and looked like success. This asserts across all four slices
  # at once, so a new slice added later fails here rather than shipping blank.
  assert {
    condition = alltrue(flatten([
      for slice in [
        output.ansible_inventory.containers,
        output.ansible_inventory.vms,
        output.ansible_inventory.docker_vms,
        output.ansible_inventory.splunk_vm,
        ] : [
        for k, g in slice : can(g.cpu_cores) && can(g.memory_mb) && can(g.disk_gb)
      ]
    ]))
    error_message = "a guest slice publishes no sizing; every slice must, or those guests read null in Nautobot while the others look fine"
  }

  # splunk_vm is a single fixed key, so it is never empty and needs no
  # non-emptiness guard -- unlike the maps above, where alltrue([]) is TRUE.
  assert {
    condition     = output.ansible_inventory.splunk_vm.splunk.cpu_cores > 0 && output.ansible_inventory.splunk_vm.splunk.disk_gb > 0
    error_message = "the splunk guest must carry positive sizing; it is built by its own module and was missed when vms was fixed"
  }
}

# WHERE a guest's root disk lives must reach the inventory, not just how big it
# is. Cost of it being absent, paid on 2026-08-24: six guests moved from rpool
# to ssd on one node, and the sanoid policy — which can only name datasets it
# can compute — kept snapshotting the old rpool paths. Those paths still held
# the retained pre-move copies, so snapshot counts and timestamps stayed
# healthy while capturing nothing live, on two OpenBao raft voters.
run "ansible_inventory_publishes_container_datastore" {
  command = plan

  # Its own fixture, and deliberately BOTH shapes: one guest that names a
  # datastore explicitly and one that says nothing and must inherit the node
  # default. `alltrue([])` is TRUE, so a single-shape fixture would let the
  # inherit case rot undetected — which is the case that actually matters,
  # because an unset datastore_id is null and null is the failure mode.
  variables {
    datastore_default = "local-zfs"
    containers = {
      "ds-explicit" = {
        node_name        = "proxmox-1"
        vm_id            = 197
        hostname         = "ds-explicit"
        vlan             = "dns"
        cpu_cores        = 1
        memory_dedicated = 512
        root_disk        = { size = 8, datastore_id = "ssd" }
      }
      "ds-inherits" = {
        node_name        = "proxmox-1"
        vm_id            = 196
        hostname         = "ds-inherits"
        vlan             = "dns"
        cpu_cores        = 1
        memory_dedicated = 512
        root_disk        = { size = 8 }
      }
    }
  }

  assert {
    condition     = length(output.ansible_inventory.containers) == 2
    error_message = "the datastore fixture did not reach the output, so every assertion below would pass vacuously"
  }

  assert {
    condition     = alltrue([for k, c in output.ansible_inventory.containers : can(c.datastore)])
    error_message = "every published container must carry datastore; without it no downstream consumer can compute the guest's dataset path, and a snapshot policy silently keeps naming the old pool"
  }

  # The explicit value must survive unchanged.
  assert {
    condition     = output.ansible_inventory.containers["ds-explicit"].datastore == "ssd"
    error_message = "an explicitly declared root_disk.datastore_id must be published verbatim"
  }

  # The whole point of the coalesce: a guest that declares nothing must publish
  # the EFFECTIVE datastore it will actually be created on, never null. A plain
  # attribute read passes the can() check above while publishing null here.
  assert {
    condition     = output.ansible_inventory.containers["ds-inherits"].datastore == "local-zfs"
    error_message = "a container with no declared datastore_id must publish the node default, not null; null is exactly what makes a consumer fall back to a hardcoded pool"
  }

  # Belt and braces on the same failure: null is falsy-ish in odd ways, so pin
  # non-emptiness independently of the two equality checks above.
  assert {
    condition     = alltrue([for k, c in output.ansible_inventory.containers : c.datastore != null && c.datastore != ""])
    error_message = "published datastore must never be null or empty"
  }
}

# Same contract on the VM side, and it is NOT redundant with the container run
# above: the two resolve the datastore differently. A container's
# root_disk.datastore_id is optional with no default and needs a coalesce; a
# VM's boot_disk.datastore_id is optional(string, "local-lvm") and is therefore
# never null, so it is a plain read. Publishing it for containers only left the
# actual VMs blank — including Splunk's, whose disks pve-w1700's sanoid policy
# names literally.
run "ansible_inventory_publishes_vm_datastore" {
  command = plan

  variables {
    vms = {
      "vm-ds-explicit" = {
        vm_id     = 212
        node_name = "proxmox-1"
        name      = "vm-ds-explicit"
        vlan      = "apps"
        tags      = ["docker"]
        boot_disk = { size = 32, datastore_id = "nvme" }
      }
      "vm-ds-default" = {
        vm_id     = 213
        node_name = "proxmox-1"
        name      = "vm-ds-default"
        vlan      = "apps"
      }
    }
  }

  assert {
    condition     = length(output.ansible_inventory.vms) == 2
    error_message = "the vm datastore fixture did not reach the output, so every assertion below would pass vacuously"
  }

  assert {
    condition     = alltrue([for k, v in output.ansible_inventory.vms : can(v.datastore)])
    error_message = "every published VM must carry datastore; without it a snapshot policy for a VM disk has to hardcode a pool"
  }

  assert {
    condition     = output.ansible_inventory.vms["vm-ds-explicit"].datastore == "nvme"
    error_message = "an explicitly declared boot_disk.datastore_id must be published verbatim"
  }

  # The type's own default, not null. This is what makes the plain read correct
  # here while the container side needs a coalesce.
  assert {
    condition     = output.ansible_inventory.vms["vm-ds-default"].datastore == "local-lvm"
    error_message = "a VM with no declared boot_disk.datastore_id must publish the type default"
  }

  assert {
    condition     = alltrue([for k, v in output.ansible_inventory.vms : v.datastore != null && v.datastore != ""])
    error_message = "published VM datastore must never be null or empty"
  }

  # docker_vms republishes the same guests under a second key. It had drifted
  # from the vms block before on the sizing fields, so pin the placement field
  # here rather than trusting the two maps to stay in step.
  assert {
    condition     = alltrue([for k, v in output.ansible_inventory.docker_vms : v.datastore != null && v.datastore != ""])
    error_message = "docker_vms is a filtered VIEW of vms and must carry datastore too"
  }

  assert {
    condition     = output.ansible_inventory.docker_vms["vm-ds-explicit"].datastore == "nvme"
    error_message = "docker_vms must publish the same datastore as the vms entry for the same guest"
  }
}

# Every disk a VM actually has, not just its boot disk. `datastore` alone
# advertises coverage that misses the data: docker VM 250 keeps 100G on a
# SECOND disk, so a snapshot policy reading only `datastore` would protect the
# 50G boot volume and silently skip the 100G one.
#
# `path` is READ BACK from the provider (path_in_datastore), never derived by
# counting declared disks. Indices are allocated per (vmid, storage) as
# next-free, so counting is wrong wherever a volume was ever moved -- VM 200
# has fast:vm-200-disk-0 as a RETAINED pre-move rollback and disk-1 as the live
# cold disk. A count-derivation would name the frozen copy.
run "ansible_inventory_publishes_every_vm_disk" {
  command = plan

  variables {
    vms = {
      "multi-disk" = {
        vm_id     = 214
        node_name = "proxmox-1"
        name      = "multi-disk"
        vlan      = "apps"
        tags      = ["docker"]
        boot_disk = { size = 50, datastore_id = "ssd", interface = "scsi0" }
        additional_disks = [
          { interface = "scsi1", size = 100, datastore_id = "ssd" },
        ]
      }
    }
  }

  assert {
    condition     = length(output.ansible_inventory.vms) == 1
    error_message = "the multi-disk fixture did not reach the output, so every assertion below would pass vacuously"
  }

  assert {
    condition     = can(output.ansible_inventory.vms["multi-disk"].disks)
    error_message = "every published VM must carry a disks list; without it a consumer can only see the boot disk"
  }

  # The whole point: BOTH disks, not one. A boot-disk-only publish passes the
  # can() check above while silently halving coverage.
  assert {
    condition     = length(output.ansible_inventory.vms["multi-disk"].disks) == 2
    error_message = "a VM declaring a boot disk plus one additional disk must publish TWO disks; publishing one is the silent-half-coverage failure this run exists to catch"
  }

  # Every entry must be usable as a dataset path. A null/empty path is worse
  # than a missing key: it renders as "<pool>/" and looks plausible.
  assert {
    condition = alltrue([
      for d in output.ansible_inventory.vms["multi-disk"].disks :
      d.datastore != null && d.datastore != "" && d.path != null && d.path != ""
    ])
    error_message = "each published disk needs a non-empty datastore AND path; either being empty yields a plausible-looking but wrong dataset path"
  }

  assert {
    condition = alltrue([
      for d in output.ansible_inventory.vms["multi-disk"].disks : d.datastore == "ssd"
    ])
    error_message = "each disk must publish its OWN datastore, not the VM's boot datastore"
  }

  # docker_vms is a filtered view of the same guests and had already drifted
  # from vms once on the sizing fields.
  assert {
    condition     = length(output.ansible_inventory.docker_vms["multi-disk"].disks) == 2
    error_message = "docker_vms must publish the same disks list as the vms entry for the same guest"
  }
}

# Splunk's own disks. This guest is built by a dedicated module, so it is NOT in
# var.vms and gets none of the vms-block coverage. `splunk_storage` is DECLARED
# shape only (literally var.tiered_disks) and carries no volume NAME, so before
# this nothing downstream could build Splunk's dataset paths -- which is exactly
# why pve-w1700's sanoid policy names `rpool/data/vm-200-disk-0` literally.
run "ansible_inventory_publishes_splunk_vm_disks" {
  command = plan

  # NOTE ON WHAT A PLAN-TIME TEST CAN AND CANNOT PROVE HERE.
  # `path` comes from path_in_datastore, a COMPUTED attribute. For a resource
  # being created, it is unknown at plan time, so asserting on its VALUE proves
  # nothing -- and iterating the list errors outright with "Iteration over null
  # value". So this run pins only what is knowable statically: that the key is
  # declared and reaches the output at all. Publishing it for containers and
  # var.vms guests while silently omitting Splunk is the regression worth
  # catching, and that is a shape question, not a value one.
  #
  # The VALUE is verified where it is actually knowable: in the apply-time plan
  # diff, which must show `+ path = "vm-200-disk-N"` with the REAL Proxmox-
  # assigned index -- never a counted 0..n-1. On this guest that distinction is
  # load-bearing: fast:vm-200-disk-0 is the retained pre-move rollback and
  # disk-1 is the live cold disk.
  assert {
    condition     = can(output.ansible_inventory.splunk_vm.splunk.disks)
    error_message = "splunk_vm must declare a disks list; splunk_storage is declared shape only (literally var.tiered_disks) and carries no volume name, so without this a snapshot policy has to hardcode Splunk's dataset paths -- which is exactly what pve-w1700's sanoid.conf does today"
  }
}

# --- ingress: dashboard audience + presentation contract ---
#
# ui, section and desc are all derived — from sso, from route count per guest,
# and from the guest's summary. Nothing is tabulated per service, so these
# assertions guard the derivation rather than a list.
run "ansible_inventory_ingress_carries_audience_metadata" {
  command = plan

  variables {
    # vikunja (a UI that opts OUT of sso), s3 (machine-only) and one hermes
    # agent — the three cases these assertions distinguish between.
    containers = {
      "vikunja" = {
        summary   = "Task and Kanban tracking"
        vm_id     = 310310
        node_name = "proxmox-1"
        hostname  = "vikunja"
        vlan      = "apps"
        dhcp      = true
      }
      "s3" = {
        vm_id     = 311311
        node_name = "proxmox-1"
        hostname  = "s3"
        vlan      = "siem"
        dhcp      = true
      }
      # Same dependency-tag set the variables suite uses for a valid agent; a
      # bare hermes-agent tag is rejected by the containers validation.
      "hermes-agent" = {
        summary   = "Hermes agent"
        vm_id     = 517000
        node_name = "proxmox-1"
        hostname  = "hermes-agent"
        vlan      = "ai"
        dhcp      = true
        tags      = ["terraform", "container", "hermes-agent", "chromium", "hindsight-client", "firecrawl-client"]
      }
    }
    domain = "example.com"
  }

  assert {
    condition = alltrue([
      for r in output.ansible_inventory.ingress : can(r.ui) && can(r.desc) && can(r.section)
    ])
    error_message = "every ingress route must publish ui/desc/section; a board cannot split or annotate without them"
  }

  # ui tracks sso, EXCEPT for the human UIs that skip the gate. vikunja is
  # sso=false and ui=true: if the exception list is dropped it lands in the
  # machine column.
  assert {
    condition = (
      one([for r in output.ansible_inventory.ingress : r if r.name == "vikunja"]).ui == true &&
      one([for r in output.ansible_inventory.ingress : r if r.name == "vikunja"]).sso == false
    )
    error_message = "vikunja must be sso=false AND ui=true — it is the case that proves ui is not just sso"
  }

  assert {
    condition     = one([for r in output.ansible_inventory.ingress : r if r.name == "s3"]).ui == false
    error_message = "a machine route (sso=false) must publish ui=false without being listed anywhere"
  }

  # desc comes from the guest's summary in deployment.json, not a table here.
  assert {
    condition     = one([for r in output.ansible_inventory.ingress : r if r.name == "vikunja"]).desc == "Task and Kanban tracking"
    error_message = "desc must come from the owning guest's summary"
  }

  # section is DERIVED from route count per guest. hermes-agent serves five,
  # so it is a section; vikunja serves one, so it is not.
  assert {
    condition = alltrue([
      for r in output.ansible_inventory.ingress :
      r.section == "hermes-agent" if r.owner == "hermes-agent"
    ])
    error_message = "a guest serving several routes must derive a section from its own name"
  }

  assert {
    condition     = one([for r in output.ansible_inventory.ingress : r if r.name == "vikunja"]).section == null
    error_message = "a guest serving one route must have no section"
  }
}

