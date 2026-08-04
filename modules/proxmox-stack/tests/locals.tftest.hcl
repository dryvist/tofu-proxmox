# Tests for locals.tf - per-VLAN IP derivation and pipeline constants
#
# All runs use mock providers (no real infrastructure needed).
# command = plan is sufficient since locals are evaluated at plan time.
#
# network_cidrs fixture is DERIVED from vlan_ids as 192.168.<vlan_id>.0/24, so the
# third octet always equals the VLAN id (RFC1918 192.168/16, never the real range).
# Real subnets come from OpenBao NETWORK_CIDR_* at runtime; these fakes exercise the
# cidrhost() math identically. Every guest IP is cidrhost(network_cidrs[vlan], vm_id);
# gateway is the .1.

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
  # vlan_ids uses its variable default (single source of truth); network_cidrs is
  # derived from it as 192.168.<vlan_id>.0/24 — no duplicated VLAN/CIDR list.
  network_cidrs           = { for name, id in var.vlan_ids : name => "192.168.${id}.0/24" }
  vm_ssh_public_key       = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestKeyData test@test"
  proxmox_ssh_private_key = "-----BEGIN OPENSSH PRIVATE KEY-----\ntest\n-----END OPENSSH PRIVATE KEY-----"
}

# --- per-guest IP derivation tests ---

run "container_ipv4_uses_vlan_cidr" {
  command = plan

  variables {
    # A domain is required to exercise the FQDN branch: with the default empty
    # domain a leased guest advertises a bare hostname, which would not prove the
    # name-not-address contract below.
    domain = "example.com"
    containers = {
      "technitium-dns" = { node_name = "proxmox-1", vm_id = 103, hostname = "technitium-dns", vlan = "dns" }
      # Rebuilt pipeline-tier guest: siem VLAN (40), DHCP-first with a positional
      # VMID (candidate id — final allocation confirmed against the private
      # allocation table before the rebuild apply).
      "haproxy" = { node_name = "proxmox-1", vm_id = 421040, hostname = "haproxy", vlan = "siem", dhcp = true }
    }
  }

  assert {
    condition     = local.container_ipv4["technitium-dns"] == "192.168.2.103/24"
    error_message = "dns-VLAN container 103 should be 192.168.2.103/24, got ${local.container_ipv4["technitium-dns"]}"
  }

  assert {
    condition     = local.container_gateway["technitium-dns"] == "192.168.2.1"
    error_message = "dns-VLAN gateway should be 192.168.2.1, got ${local.container_gateway["technitium-dns"]}"
  }

  # A guest resolves via its own VLAN gateway (which forwards the internal zone
  # onward), never via a resolver address baked in at provision time and never
  # via the node's own VLAN gateway, which a guest elsewhere may not reach.
  # Asserted by derivation, not a literal, so no real address appears here.
  assert {
    condition     = local.container_gateway["technitium-dns"] == cidrhost(var.network_cidrs["dns"], 1)
    error_message = "guest resolver must be its own VLAN gateway, got ${local.container_gateway["technitium-dns"]}"
  }

  # DHCP-first guest short-circuits cidrhost — the positional VMID must never
  # be interpreted as a /24 host number.
  assert {
    condition     = local.container_ipv4["haproxy"] == "dhcp"
    error_message = "dhcp-first siem-VLAN guest must pass through as 'dhcp', got ${local.container_ipv4["haproxy"]}"
  }

  # A leased guest advertises a NAME, never an address — there is no second
  # place holding one for it.
  assert {
    condition     = local.container_address["haproxy"] == "haproxy.${var.domain}"
    error_message = "dhcp guest must advertise its FQDN, got ${local.container_address["haproxy"]}"
  }
}

run "vm_ipv4_uses_vlan_cidr" {
  command = plan

  variables {
    vms = {
      "docker-host" = { node_name = "proxmox-1", vm_id = 250, name = "docker", vlan = "nonprod" }
      "idrac-kvm"   = { node_name = "proxmox-1", vm_id = 251, name = "idrac-kvm", vlan = "apps" }
    }
  }

  assert {
    condition     = local.vm_ipv4["docker-host"] == "192.168.90.250/24"
    error_message = "nonprod-VLAN VM 250 should be 192.168.90.250/24, got ${local.vm_ipv4["docker-host"]}"
  }

  assert {
    condition     = local.vm_gateway["docker-host"] == "192.168.90.1"
    error_message = "nonprod-VLAN gateway should be 192.168.90.1, got ${local.vm_gateway["docker-host"]}"
  }

  assert {
    condition     = local.vm_ipv4["idrac-kvm"] == "192.168.60.251/24"
    error_message = "apps-VLAN VM 251 should be 192.168.60.251/24, got ${local.vm_ipv4["idrac-kvm"]}"
  }
}

# --- splunk derivation tests (siem VLAN) ---

run "splunk_derived_ip_uses_siem_vlan" {
  command = plan

  assert {
    condition     = local.splunk_derived_ip == "192.168.40.99/24"
    error_message = "splunk_derived_ip should be siem-VLAN 192.168.40.99/24 (placeholder default splunk_vm_id), got ${local.splunk_derived_ip}"
  }

  assert {
    condition     = local.splunk_network_gateway == "192.168.40.1"
    error_message = "splunk_network_gateway should be siem-VLAN .1 (192.168.40.1), got ${local.splunk_network_gateway}"
  }
}

run "splunk_derived_ip_different_id" {
  command = plan

  variables {
    splunk_vm_id = 205
  }

  assert {
    condition     = local.splunk_derived_ip == "192.168.40.205/24"
    error_message = "splunk_derived_ip should track splunk_vm_id (205), got ${local.splunk_derived_ip}"
  }
}

# --- management_network test (compute VLAN CIDR) ---

run "management_network_is_compute_cidr" {
  command = plan

  assert {
    condition     = local.management_network == "192.168.10.0/24"
    error_message = "management_network should be the compute VLAN CIDR 192.168.10.0/24, got ${local.management_network}"
  }
}

# --- splunk_network_ips tests (siem VLAN, host-form) ---

run "splunk_network_ips_default_no_containers" {
  command = plan

  variables {
    containers = {}
  }

  assert {
    condition     = length(local.splunk_network_ips) == 1
    error_message = "splunk_network_ips with no splunk containers should have exactly 1 entry, got ${length(local.splunk_network_ips)}"
  }

  assert {
    condition     = contains(local.splunk_network_ips, "192.168.40.99")
    error_message = "splunk_network_ips should contain splunk VM IP 192.168.40.99 (placeholder default)"
  }
}

run "splunk_network_ips_includes_splunk_tagged_container" {
  command = plan

  variables {
    containers = {
      "splunk-mgmt" = {
        vm_id     = 199
        node_name = "proxmox-1"
        hostname  = "splunk-mgmt"
        vlan      = "siem"
        tags      = ["terraform", "splunk", "container"]
      }
    }
  }

  assert {
    condition     = contains(local.splunk_network_ips, "192.168.40.99")
    error_message = "splunk_network_ips must include splunk VM IP"
  }

  assert {
    condition     = contains(local.splunk_network_ips, "192.168.40.199")
    error_message = "splunk_network_ips must include splunk-tagged container IP on siem VLAN"
  }

  assert {
    condition     = length(local.splunk_network_ips) == 2
    error_message = "splunk_network_ips should have exactly 2 entries"
  }
}

# --- pipeline_constants tests ---

run "pipeline_constants_service_ports" {
  command = plan

  assert {
    condition     = local.pipeline_constants.service_ports.splunk_hec == 8088
    error_message = "splunk_hec port should be 8088"
  }

  assert {
    condition     = local.pipeline_constants.service_ports.splunk_web == 8000
    error_message = "splunk_web port should be 8000"
  }

  assert {
    condition     = local.pipeline_constants.service_ports.haproxy_stats == 8404
    error_message = "haproxy_stats port should be 8404"
  }
}

run "pipeline_constants_monitoring_ports" {
  command = plan

  assert {
    condition     = local.pipeline_constants.service_ports.smokeping_web == 80
    error_message = "smokeping_web port should be 80"
  }

  assert {
    condition     = local.pipeline_constants.service_ports.speedtest_exporter == 9798
    error_message = "speedtest_exporter port should be 9798"
  }

  # Hardened Prometheus-native stack exporters (see docs/SMOKEPING.md)
  assert {
    condition     = local.pipeline_constants.service_ports.smokeping_prober == 9374
    error_message = "smokeping_prober port should be 9374"
  }

  assert {
    condition     = local.pipeline_constants.service_ports.blackbox_exporter == 9115
    error_message = "blackbox_exporter port should be 9115"
  }

  assert {
    condition     = local.pipeline_constants.service_ports.atlas_exporter == 9400
    error_message = "atlas_exporter port should be 9400"
  }

  assert {
    condition     = local.pipeline_constants.service_ports.irtt == 2112
    error_message = "irtt port should be 2112"
  }
}

run "pipeline_constants_syslog_ports" {
  command = plan

  # Legacy flat map is derived from syslog_port_map (high ports + default 514)
  assert {
    condition     = local.pipeline_constants.syslog_ports.unifi == 1514
    error_message = "unifi syslog port should be 1514"
  }

  assert {
    condition     = local.pipeline_constants.syslog_ports.palo_alto == 1515
    error_message = "palo_alto syslog port should be 1515"
  }

  assert {
    condition     = local.pipeline_constants.syslog_ports.default == 514
    error_message = "default syslog port should be 514"
  }
}

run "pipeline_constants_syslog_port_map" {
  command = plan

  assert {
    condition     = local.pipeline_constants.syslog_port_map.unifi.standard == 514
    error_message = "unifi standard frontend should be 514"
  }

  assert {
    condition     = local.pipeline_constants.syslog_port_map.unifi.high == 1514
    error_message = "unifi high backend should be 1514"
  }

  assert {
    condition     = local.pipeline_constants.syslog_port_map.palo_alto.index == "firewall"
    error_message = "palo_alto must route to the firewall index"
  }

  assert {
    condition     = local.pipeline_constants.syslog_port_map.windows.sourcetype == "syslog"
    error_message = "windows sourcetype should be syslog"
  }

  # Every family keeps the high = standard + 1000 convention
  assert {
    condition = alltrue([
      for k, v in local.pipeline_constants.syslog_port_map : v.high == v.standard + 1000
    ])
    error_message = "every syslog_port_map family must keep high == standard + 1000"
  }
}

run "pipeline_constants_netflow_ports" {
  command = plan

  assert {
    condition     = local.pipeline_constants.netflow_ports.unifi == 2055
    error_message = "unifi netflow port should be 2055"
  }
}

run "pipeline_constants_notification_ports" {
  command = plan

  assert {
    condition     = local.pipeline_constants.notification_ports.mailpit_smtp == 1025
    error_message = "mailpit_smtp port should be 1025"
  }

  assert {
    condition     = local.pipeline_constants.notification_ports.mailpit_web == 8025
    error_message = "mailpit_web port should be 8025"
  }

  assert {
    condition     = local.pipeline_constants.notification_ports.ntfy_http == 8080
    error_message = "ntfy_http port should be 8080"
  }
}

run "pipeline_constants_cribl_ports" {
  command = plan

  assert {
    condition     = local.pipeline_constants.service_ports.cribl_edge_api == 9420
    error_message = "cribl_edge_api port should be 9420"
  }

  assert {
    condition     = local.pipeline_constants.service_ports.cribl_stream_api == 9000
    error_message = "cribl_stream_api port should be 9000"
  }
}

run "pipeline_constants_vector_db_ports" {
  command = plan

  assert {
    condition     = local.pipeline_constants.vector_db_ports.qdrant_http == 6333
    error_message = "qdrant_http port should be 6333"
  }

  assert {
    condition     = local.pipeline_constants.vector_db_ports.qdrant_grpc == 6334
    error_message = "qdrant_grpc port should be 6334"
  }
}

run "pipeline_constants_memory_ports" {
  command = plan

  assert {
    condition     = local.pipeline_constants.memory_ports.hindsight_api == 8888
    error_message = "hindsight_api port should be 8888"
  }

  assert {
    condition     = local.pipeline_constants.memory_ports.hindsight_cp == 9999
    error_message = "hindsight_cp port should be 9999"
  }
}

run "pipeline_constants_db_ports" {
  command = plan

  assert {
    condition     = local.pipeline_constants.service_ports.postgres_default == 5432
    error_message = "postgres_default port should be 5432"
  }

  assert {
    condition     = local.pipeline_constants.service_ports.redis_default == 6379
    error_message = "redis_default port should be 6379"
  }
}

run "pipeline_constants_serving" {
  command = plan

  # The single definition of LLM serving concurrency. ansible-proxmox-ai
  # derives ai_llm_concurrency from this; nix-darwin's serveConcurrency is
  # checked against it by CI. See the comment on serving in constants.tf.
  assert {
    condition     = local.pipeline_constants.serving.llm_concurrency == 1
    error_message = "serving.llm_concurrency should be 1"
  }

  # The serving host publishes as EMPTY when the deployment object does not
  # describe it. This is the property that keeps its address out of public git:
  # the repository holds the shape, the private deployment object holds the
  # value. A committed default here — any address at all — would put the value
  # back into every clone, which is the defect this pair of keys exists to fix.
  assert {
    condition     = local.pipeline_constants.serving.host == ""
    error_message = "serving.host must publish empty when unset — a committed default would recreate the literal this key replaced."
  }
  assert {
    condition     = local.pipeline_constants.serving.ip == ""
    error_message = "serving.ip must publish empty when unset — a committed default would recreate the literal this key replaced."
  }
}

run "pipeline_constants_serving_published_when_supplied" {
  command = plan

  # The other half of the contract: a value supplied at apply time reaches
  # consumers unchanged. Without this the empty-by-default assertions above
  # would also pass on a key that is hardcoded empty and never wired to
  # anything, which is a shape that publishes nothing and fails silently.
  variables {
    llm_large_serving_host = "llm-large-example"
    llm_large_serving_ip   = "192.0.2.10"
  }

  assert {
    condition     = local.pipeline_constants.serving.host == "llm-large-example"
    error_message = "serving.host must publish the supplied hostname unchanged."
  }
  assert {
    condition     = local.pipeline_constants.serving.ip == "192.0.2.10"
    error_message = "serving.ip must publish the supplied address unchanged."
  }
}

# --- tag-filtering locals isolation ---

run "cribl_stream_ids_empty_by_default" {
  command = plan

  variables {
    containers = {}
  }

  assert {
    condition     = length(local.cribl_stream_container_ids) == 0
    error_message = "cribl_stream_container_ids should be empty when containers is empty"
  }
}

run "monitoring_ids_empty_by_default" {
  command = plan

  variables {
    containers = {}
  }

  assert {
    condition     = length(local.monitoring_container_ids) == 0
    error_message = "monitoring_container_ids should be empty when containers is empty"
  }
}

run "monitoring_ids_picks_up_monitoring_tagged" {
  command = plan

  variables {
    containers = {
      "smokeping" = {
        vm_id     = 990001
        node_name = "proxmox-1"
        dhcp      = true
        hostname  = "smokeping"
        vlan      = "mgmt"
        tags      = ["terraform", "container", "monitoring", "docker"]
      }
    }
  }

  assert {
    condition     = local.monitoring_container_ids["smokeping"] == 990001
    error_message = "monitoring_container_ids should map 'smokeping' to its 6-digit VMID 990001"
  }

  # DNS-first guest: no vm_id-derived IP. cidrhost is skipped (a 6-digit id would
  # overflow the /24 host space), so container_ipv4 is the literal "dhcp".
  assert {
    condition     = local.container_ipv4["smokeping"] == "dhcp"
    error_message = "dhcp smokeping container_ipv4 should be \"dhcp\" (cidrhost skipped), got ${local.container_ipv4["smokeping"]}"
  }
}

# DNS-first (dhcp) addressing: a 6-digit positional VMID skips IP derivation, the
# guest advertises its FQDN ({hostname}.{domain}) to downstream consumers, and no
# gateway is derived (the DHCP lease provides one).
run "container_dhcp_resolves_fqdn_and_null_gateway" {
  command = plan

  variables {
    domain = "example.com"
    containers = {
      "speedtest" = {
        vm_id     = 990002
        node_name = "proxmox-1"
        dhcp      = true
        hostname  = "speedtest"
        vlan      = "mgmt"
        tags      = ["terraform", "container", "monitoring", "docker"]
      }
    }
  }

  assert {
    condition     = local.container_address["speedtest"] == "speedtest.example.com"
    error_message = "dhcp speedtest should advertise FQDN speedtest.example.com, got ${local.container_address["speedtest"]}"
  }

  assert {
    condition     = local.container_gateway["speedtest"] == null
    error_message = "dhcp speedtest container_gateway should be null (lease-provided)"
  }
}

# Static-IP exception host (a DNS server, reachable before DNS is up) carrying a
# 7-digit positional VMID. cidrhost(<dns cidr>, 9900001) would overflow the /24,
# so this run only passes because the static ip_config short-circuits the derive
# branch — the regression guard for the coalesce -> if/else change in locals.tf.
run "container_static_ip_with_positional_vmid_skips_cidrhost" {
  command = plan

  variables {
    containers = {
      "technitium-dns-2" = {
        vm_id     = 9900001
        node_name = "proxmox-1"
        hostname  = "technitium-dns-2"
        vlan      = "dns"
        ip_config = { ipv4_address = "192.168.2.3/24" }
        tags      = ["terraform", "container", "dns"]
      }
    }
  }

  assert {
    condition     = local.container_ipv4["technitium-dns-2"] == "192.168.2.3/24"
    error_message = "static ip_config must win without evaluating cidrhost for the 7-digit vm_id, got ${local.container_ipv4["technitium-dns-2"]}"
  }

  assert {
    condition     = local.container_gateway["technitium-dns-2"] == "192.168.2.1"
    error_message = "static positional-VMID guest gateway should be the .1 of its VLAN, got ${local.container_gateway["technitium-dns-2"]}"
  }
}

run "cribl_stream_ids_picks_up_stream_tagged" {
  command = plan

  variables {
    containers = {
      "cribl-stream" = {
        vm_id     = 425040
        node_name = "proxmox-1"
        dhcp      = true
        hostname  = "cribl-stream"
        vlan      = "siem"
        tags      = ["terraform", "cribl", "stream", "container"]
      }
    }
  }

  assert {
    condition     = length(local.cribl_stream_container_ids) == 1
    error_message = "cribl_stream_container_ids should have 1 entry for cribl+stream tagged container"
  }

  assert {
    condition     = local.cribl_stream_container_ids["cribl-stream"] == 425040
    error_message = "cribl_stream_container_ids should map 'cribl-stream' to vm_id 425040"
  }
}

# A guest's resolver is its own VLAN gateway, which conditionally forwards the
# internal zone to the resolver fleet. container_gateway is the value the
# container module now feeds into initialization.dns.servers, so pinning it here
# pins the resolver each guest is handed.
#
# The point is what is ABSENT: no resolver address is baked into a guest, so
# renaming or renumbering the fleet cannot leave a guest holding a stale list —
# the failure this replaced, and the reason two resolvers ended up sharing one
# address to stay reachable.
run "guest_resolver_is_its_own_vlan_gateway" {
  command = plan

  variables {
    containers = {
      # Static guest on the dns VLAN.
      "technitium10" = {
        vm_id     = 103, hostname = "technitium10", vlan = "dns"
        node_name = "proxmox-1"
        ip_config = { ipv4_address = "192.0.2.2/24" }
      }
      # Static guest on a DIFFERENT VLAN — must get ITS gateway, not the dns
      # VLAN's and not the Proxmox node's, which is the case that would leave a
      # guest pointed at a gateway it may have no route to.
      "traefik" = {
        vm_id     = 101, hostname = "traefik", vlan = "mgmt"
        node_name = "proxmox-1"
        ip_config = { ipv4_address = "192.168.5.101/24" }
      }
    }
  }

  assert {
    condition     = local.container_gateway["technitium10"] == cidrhost(var.network_cidrs["dns"], 1)
    error_message = "a dns-VLAN guest must resolve via the dns VLAN gateway, got ${local.container_gateway["technitium10"]}"
  }

  assert {
    condition     = local.container_gateway["traefik"] == cidrhost(var.network_cidrs["mgmt"], 1)
    error_message = "a guest must resolve via its OWN VLAN gateway, not another VLAN's, got ${local.container_gateway["traefik"]}"
  }
}

# DHCP guests take address and resolver from the lease. A null gateway is what
# makes the container module omit servers entirely so the lease wins.
run "dhcp_guest_takes_its_resolver_from_the_lease" {
  command = plan

  variables {
    containers = {
      # A leased guest declares nothing about its address — no octet, no
      # reservation. That is the whole point.
      "dhcp-guest" = { node_name = "proxmox-1", vm_id = 601, hostname = "dhcp-guest", vlan = "apps", dhcp = true }
    }
  }

  assert {
    condition     = local.container_gateway["dhcp-guest"] == null
    error_message = "a DHCP guest must have no derived gateway, so cloud-init omits servers and the lease supplies the resolver"
  }
}

# --- deterministic MAC contract (DHCP-first guests) ---
#
# DHCP-first LXCs carry a stable, locally-administered MAC (02:-prefixed digest of
# the hostname). It exists for LEASE STABILITY: same MAC across a rebuild means
# the same lease, so the guest keeps its address and its lease-table DNS name. It
# is not a reservation key — nothing reserves an address for these guests, and
# nothing publishes one for them.

run "container_mac_is_deterministic_locally_administered" {
  command = plan

  variables {
    containers = {
      "smokeping" = {
        vm_id     = 990001
        node_name = "proxmox-1"
        dhcp      = true
        hostname  = "smokeping"
        vlan      = "mgmt"
        tags      = ["terraform", "container", "monitoring", "docker"]
      }
    }
  }

  # 02: prefix => locally-administered + unicast (RFC 7042).
  assert {
    condition     = startswith(local.container_mac["smokeping"], "02:")
    error_message = "container_mac must be locally-administered (02:-prefixed), got ${local.container_mac["smokeping"]}"
  }

  # Canonical 6-octet colon-separated form (17 chars: 02 + 5*':'+2 hex).
  assert {
    condition     = length(local.container_mac["smokeping"]) == 17
    error_message = "container_mac must be a 17-char MAC (02:xx:xx:xx:xx:xx), got ${local.container_mac["smokeping"]}"
  }

  # Deterministic: equals the md5-digest format() recomputed from the same hostname.
  assert {
    condition = local.container_mac["smokeping"] == format("02:%s:%s:%s:%s:%s",
      substr(md5("smokeping"), 0, 2), substr(md5("smokeping"), 2, 2),
    substr(md5("smokeping"), 4, 2), substr(md5("smokeping"), 6, 2), substr(md5("smokeping"), 8, 2))
    error_message = "container_mac must be the deterministic md5(hostname) digest, got ${local.container_mac["smokeping"]}"
  }
}

# The published inventory must expose exactly ONE address authority per guest: a
# leased guest gets a name and no address anywhere; a static guest gets the
# address it declared. This is the regression guard against reintroducing a
# second copy of a leased guest's address.
run "inventory_publishes_one_address_authority_per_guest" {
  command = plan

  variables {
    # See the note in container_ipv4_uses_vlan_cidr: a domain is needed for the
    # FQDN branch to be reachable at all.
    domain = "example.com"
    containers = {
      # Leased guest with a 6-digit positional VMID — the /24 cidrhost math
      # cannot express it, which is exactly why it must not carry an address.
      "netq-probe-media" = {
        vm_id     = 990003
        node_name = "proxmox-1"
        dhcp      = true
        hostname  = "netq-probe-media"
        vlan      = "media_svc"
        tags      = ["terraform", "container", "monitoring", "docker"]
      }
      # Static guest: its address is declared once, by derivation from its VMID.
      "apt-cacher-ng" = {
        vm_id     = 108
        node_name = "proxmox-1"
        hostname  = "apt-cacher-ng"
        vlan      = "compute"
      }
    }
  }

  # A leased guest is published by name only.
  assert {
    condition     = output.ansible_inventory.containers["netq-probe-media"].ip == "netq-probe-media.${var.domain}"
    error_message = "leased guest must be published as an FQDN, got ${output.ansible_inventory.containers["netq-probe-media"].ip}"
  }

  # No reserved address is published for anyone — the field is gone, so a
  # consumer cannot resurrect a second authority by reading it.
  assert {
    condition     = alltrue([for k, c in output.ansible_inventory.containers : !can(c.reserved_ip)])
    error_message = "the inventory must not publish a reserved address for any guest"
  }

  # Static guest carries no DHCP MAC — nothing to stabilize, its address is declared.
  assert {
    condition     = output.ansible_inventory.containers["apt-cacher-ng"].mac == null
    error_message = "static guest inventory mac must be null"
  }

  # Asserted by derivation, not a literal, so no real address appears here.
  assert {
    condition     = output.ansible_inventory.containers["apt-cacher-ng"].ip == cidrhost(var.network_cidrs["compute"], 108)
    error_message = "static guest must publish its derived address, got ${output.ansible_inventory.containers["apt-cacher-ng"].ip}"
  }

  # The leased guest keeps its lease-stabilizing MAC.
  assert {
    condition     = startswith(output.ansible_inventory.containers["netq-probe-media"].mac, "02:")
    error_message = "leased guest inventory mac must be the 02:-prefixed deterministic MAC"
  }
}

# --- ai_log_routing tests (routing truth derives from ai_log_ports) ---

run "ai_log_routing_ports_track_ai_log_ports" {
  command = plan

  # Same key set, and every routing port equals its ai_log_ports twin — the
  # routing map is derived, so a drifted port is impossible by construction;
  # this asserts the derivation itself stays wired.
  assert {
    condition     = keys(local.ai_log_routing) == keys(local.ai_log_ports)
    error_message = "ai_log_routing must have exactly the ai_log_ports key set"
  }

  assert {
    condition     = alltrue([for name, r in local.ai_log_routing : r.port == local.ai_log_ports[name]])
    error_message = "every ai_log_routing port must equal its ai_log_ports twin"
  }

  assert {
    condition     = alltrue([for name, r in local.ai_log_routing : length(r.index) > 0 && length(r.sourcetype) > 0])
    error_message = "every ai_log_routing entry needs a non-empty index and sourcetype"
  }
}

run "ai_log_routing_exported_in_pipeline_constants" {
  command = plan

  assert {
    condition     = local.pipeline_constants.ai_log_routing == local.ai_log_routing
    error_message = "pipeline_constants must surface ai_log_routing for the ansible_inventory consumers"
  }

  assert {
    condition     = local.pipeline_constants.ai_log_routing.claude_code.index == "claude"
    error_message = "claude_code must route to index=claude"
  }

  assert {
    condition     = local.pipeline_constants.ai_log_routing.openbao_audit.sourcetype == "openbao:audit"
    error_message = "openbao_audit must carry sourcetype openbao:audit"
  }
}

# --- media_container_ids tag-filter tests ---
# The vpn-tag exclusion is security-critical: the VPN-locked downloader must
# NOT get a stacked hypervisor DROP/DROP under its in-guest killswitch (and it
# has no media_web_rules entry, so a stacked firewall would also drop all
# inbound web traffic). Guard the filter, not just the static port map.

run "media_container_ids_excludes_vpn_tagged_downloader" {
  command = plan

  variables {
    containers = {
      "download-vpn" = {
        vm_id     = 210
        node_name = "proxmox-1"
        hostname  = "download-vpn"
        vlan      = "media_svc"
        tags      = ["terraform", "container", "media", "vpn"]
      }
      "sonarr" = {
        vm_id     = 211
        node_name = "proxmox-1"
        hostname  = "sonarr"
        vlan      = "media_svc"
        tags      = ["terraform", "container", "media", "sonarr"]
      }
      "no-media-tag" = {
        vm_id     = 212
        node_name = "proxmox-1"
        hostname  = "no-media-tag"
        vlan      = "apps"
        tags      = ["terraform", "container"]
      }
    }
  }

  assert {
    condition     = !contains(keys(local.media_container_ids), "download-vpn")
    error_message = "media_container_ids must exclude vpn-tagged guests — the killswitch is their boundary, never a stacked guest firewall"
  }

  assert {
    condition     = contains(keys(local.media_container_ids), "sonarr")
    error_message = "media_container_ids must include media-tagged LAN-only guests"
  }

  assert {
    condition     = length(local.media_container_ids) == 1
    error_message = "media_container_ids must contain exactly the media-minus-vpn set"
  }
}

# --- OpenBao Raft voter concentration arithmetic ---
# Raft survives losing VOTERS; the estate loses HOSTS. These runs pin the
# counting in checks.tf, including the counter-intuitive part: with three voters
# stacked on one node, adding a single voter buys nothing because quorum rises
# with it. Only the second added voter creates real slack.
#
# The two lopsided fixtures are expected to fail the
# terraform_data.openbao_voter_spread_guard precondition (a hard plan error
# since the advisory check was converted) — that failure IS the assertion. vm_ids here are the mgmt octet each voter owns,
# because the module derives guest IPs with cidrhost(): a real six-digit VMID does
# not fit a /24, and the containers variable rejects anything below 100.

run "openbao_concentration_seven_voters_three_on_one_node_has_no_headroom" {
  command = plan

  expect_failures = [terraform_data.openbao_voter_spread_guard]

  variables {
    containers = {
      "openbao-01" = { vm_id = 140, hostname = "openbao-01", vlan = "mgmt", node_name = "proxmox-1", tags = ["openbao"] }
      "openbao-10" = { vm_id = 110, hostname = "openbao-10", vlan = "mgmt", node_name = "proxmox-1", tags = ["openbao"] }
      "openbao-02" = { vm_id = 105, hostname = "openbao-02", vlan = "mgmt", node_name = "proxmox-2", tags = ["openbao"] }
      "openbao-20" = { vm_id = 120, hostname = "openbao-20", vlan = "mgmt", node_name = "proxmox-2", tags = ["openbao"] }
      "openbao-21" = { vm_id = 121, hostname = "openbao-21", vlan = "mgmt", node_name = "proxmox-2", tags = ["openbao"] }
      "openbao-30" = { vm_id = 130, hostname = "openbao-30", vlan = "mgmt", node_name = "proxmox-3", tags = ["openbao"] }
      "openbao-31" = { vm_id = 131, hostname = "openbao-31", vlan = "mgmt", node_name = "proxmox-3", tags = ["openbao"] }
    }
  }

  assert {
    condition     = local.openbao_voter_count == 7 && local.openbao_quorum == 4
    error_message = "7 voters must require a quorum of 4, got ${local.openbao_voter_count} voters / quorum ${local.openbao_quorum}"
  }

  # 4 survivors == quorum 4: the cluster stays up, with zero further slack.
  assert {
    condition     = local.openbao_voters_after_worst_node_loss == 4
    error_message = "losing the node carrying 3 of 7 voters must leave 4, got ${local.openbao_voters_after_worst_node_loss}"
  }
}

run "openbao_concentration_one_added_voter_still_has_no_headroom" {
  command = plan

  expect_failures = [terraform_data.openbao_voter_spread_guard]

  variables {
    containers = {
      "openbao-01" = { vm_id = 140, hostname = "openbao-01", vlan = "mgmt", node_name = "proxmox-1", tags = ["openbao"] }
      "openbao-10" = { vm_id = 110, hostname = "openbao-10", vlan = "mgmt", node_name = "proxmox-1", tags = ["openbao"] }
      "openbao-02" = { vm_id = 105, hostname = "openbao-02", vlan = "mgmt", node_name = "proxmox-2", tags = ["openbao"] }
      "openbao-20" = { vm_id = 120, hostname = "openbao-20", vlan = "mgmt", node_name = "proxmox-2", tags = ["openbao"] }
      "openbao-21" = { vm_id = 121, hostname = "openbao-21", vlan = "mgmt", node_name = "proxmox-2", tags = ["openbao"] }
      "openbao-30" = { vm_id = 130, hostname = "openbao-30", vlan = "mgmt", node_name = "proxmox-3", tags = ["openbao"] }
      "openbao-31" = { vm_id = 131, hostname = "openbao-31", vlan = "mgmt", node_name = "proxmox-3", tags = ["openbao"] }
      "openbao-41" = { vm_id = 141, hostname = "openbao-41", vlan = "mgmt", node_name = "proxmox-4", tags = ["openbao"] }
    }
  }

  # 8 voters, quorum 5, survivors 5. Quorum rose with the added voter, so the
  # slack is still zero — one new voter does not fix concentration.
  assert {
    condition     = local.openbao_quorum == 5 && local.openbao_voters_after_worst_node_loss == 5
    error_message = "8 voters must need quorum 5 and leave 5 after the worst node loss, got quorum ${local.openbao_quorum} / survivors ${local.openbao_voters_after_worst_node_loss}"
  }
}

run "openbao_concentration_two_added_voters_create_headroom" {
  command = plan

  variables {
    containers = {
      "openbao-01" = { vm_id = 140, hostname = "openbao-01", vlan = "mgmt", node_name = "proxmox-1", tags = ["openbao"] }
      "openbao-10" = { vm_id = 110, hostname = "openbao-10", vlan = "mgmt", node_name = "proxmox-1", tags = ["openbao"] }
      "openbao-02" = { vm_id = 105, hostname = "openbao-02", vlan = "mgmt", node_name = "proxmox-2", tags = ["openbao"] }
      "openbao-20" = { vm_id = 120, hostname = "openbao-20", vlan = "mgmt", node_name = "proxmox-2", tags = ["openbao"] }
      "openbao-21" = { vm_id = 121, hostname = "openbao-21", vlan = "mgmt", node_name = "proxmox-2", tags = ["openbao"] }
      "openbao-30" = { vm_id = 130, hostname = "openbao-30", vlan = "mgmt", node_name = "proxmox-3", tags = ["openbao"] }
      "openbao-31" = { vm_id = 131, hostname = "openbao-31", vlan = "mgmt", node_name = "proxmox-3", tags = ["openbao"] }
      "openbao-41" = { vm_id = 141, hostname = "openbao-41", vlan = "mgmt", node_name = "proxmox-4", tags = ["openbao"] }
      "openbao-42" = { vm_id = 142, hostname = "openbao-42", vlan = "mgmt", node_name = "proxmox-4", tags = ["openbao"] }
    }
  }

  # 9 voters, quorum 5, survivors 6 — one voter of real slack after a node loss.
  assert {
    condition     = local.openbao_quorum == 5 && local.openbao_voters_after_worst_node_loss == 6
    error_message = "9 voters must need quorum 5 and leave 6 after the worst node loss, got quorum ${local.openbao_quorum} / survivors ${local.openbao_voters_after_worst_node_loss}"
  }

  assert {
    condition     = local.openbao_voters_after_worst_node_loss > local.openbao_quorum
    error_message = "two added voters on a fourth node must produce headroom above quorum"
  }
}

# The escape hatch must actually escape: the SAME no-headroom fixture as the
# seven-voter run above, but with the degraded-window acknowledgement set —
# the plan must pass (no expect_failures) despite the concentrated map.
run "openbao_concentration_acknowledgement_permits_degraded_window" {
  command = plan

  variables {
    openbao_accept_quorum_loss_on_node_failure = true
    containers = {
      "openbao-01" = { vm_id = 140, hostname = "openbao-01", vlan = "mgmt", node_name = "proxmox-1", tags = ["openbao"] }
      "openbao-10" = { vm_id = 110, hostname = "openbao-10", vlan = "mgmt", node_name = "proxmox-1", tags = ["openbao"] }
      "openbao-02" = { vm_id = 105, hostname = "openbao-02", vlan = "mgmt", node_name = "proxmox-2", tags = ["openbao"] }
      "openbao-20" = { vm_id = 120, hostname = "openbao-20", vlan = "mgmt", node_name = "proxmox-2", tags = ["openbao"] }
      "openbao-21" = { vm_id = 121, hostname = "openbao-21", vlan = "mgmt", node_name = "proxmox-2", tags = ["openbao"] }
      "openbao-30" = { vm_id = 130, hostname = "openbao-30", vlan = "mgmt", node_name = "proxmox-3", tags = ["openbao"] }
      "openbao-31" = { vm_id = 131, hostname = "openbao-31", vlan = "mgmt", node_name = "proxmox-3", tags = ["openbao"] }
    }
  }

  # Still no headroom — the acknowledgement changes the verdict, not the math.
  assert {
    condition     = local.openbao_voters_after_worst_node_loss == local.openbao_quorum
    error_message = "fixture must still be at exactly quorum after worst-node loss, got ${local.openbao_voters_after_worst_node_loss} vs quorum ${local.openbao_quorum}"
  }
}

run "openbao_concentration_ignores_untagged_guests" {
  command = plan

  variables {
    containers = {
      "traefik" = { vm_id = 101, hostname = "traefik", vlan = "mgmt", node_name = "proxmox-1" }
    }
  }

  assert {
    condition     = local.openbao_voter_count == 0
    error_message = "only openbao-tagged guests are voters, got ${local.openbao_voter_count}"
  }
}

# The spend store is a SEPARATE guest from the routers it serves, and the tag
# filter is what keeps it that way. A store colocated with a router member would
# give each member a private spend counter, which is the miscount that made an
# earlier ceiling dishonest — so a router picking up the llm-redis tag, or the
# store picking up llm-router, is a defect and not a deployment choice.
run "llm_redis_container_ids_are_disjoint_from_the_router_pool" {
  command = plan

  variables {
    containers = {
      "llm-router-1" = {
        vm_id     = 301
        node_name = "proxmox-1"
        hostname  = "llm-router-1"
        vlan      = "ai"
        dhcp      = true
        tags      = ["terraform", "container", "llm-router"]
      }
      "llm-redis-1" = {
        vm_id     = 302
        node_name = "proxmox-1"
        hostname  = "llm-redis-1"
        vlan      = "ai"
        dhcp      = true
        tags      = ["terraform", "container", "llm-redis"]
      }
      "untagged" = {
        vm_id     = 303
        node_name = "proxmox-1"
        hostname  = "untagged"
        vlan      = "ai"
        dhcp      = true
        tags      = ["terraform", "container"]
      }
    }
  }

  assert {
    condition     = keys(local.llm_redis_container_ids) == ["llm-redis-1"]
    error_message = "llm_redis_container_ids must select exactly the llm-redis-tagged guests"
  }

  assert {
    condition = length(setintersection(
      keys(local.llm_redis_container_ids),
      keys(local.llm_router_container_ids),
    )) == 0
    error_message = "the spend store must never be colocated with a router member — a store inside one member gives every member a private counter, which is the miscount a shared store exists to remove"
  }
}
