# Native publish of the Ansible inventory to the homelab RustFS service.
#
# `tofu apply` is the publish boundary: the aws_s3_object below uploads the
# inventory whenever its content changes — no shell script, no `aws` CLI. Any
# consumer (CI via OIDC, cloud agents, ansible) fetches this object with scoped
# read creds, with no checkout and no terraform toolchain.
#
# The AWS provider uses the same ambient credential chain as the S3 *state*
# backend (native root configuration) — no static keys here.

locals {
  # The inventory value, shared by output.ansible_inventory and the publish
  # resource below (a resource cannot reference an output, so this lives here).
  ansible_inventory = {
    # Contract version of this published artifact. Consumers (and the
    # homelab-contracts JSON schema that gates the publish) read this to confirm
    # they understand the emitted shape. Bump only on a breaking key-set change.
    schema_version = "2.1.0"
    # Which desired state this came from — see the variables' own descriptions.
    desired_state = {
      etag = var.desired_state_etag
    }
    # LXC Containers - using proxmox_pct_remote connection
    containers = {
      for k, v in(length(var.containers) > 0 ? module.containers[0].container_details : {}) : k => {
        vmid     = v.id
        hostname = var.containers[k].hostname
        ip       = local.container_address[k] # static: per-VLAN cidrhost IP (CIDR stripped); DHCP guests: FQDN (DNS-first)
        # Deterministic MAC for DHCP-first guests (null for static guests). It
        # keeps the guest's lease — and therefore its address and its lease-table
        # DNS name — stable across a rebuild. It is NOT a reservation key: this
        # inventory no longer publishes a reserved address, because a leased
        # guest's address exists only in the lease. Consumers address these guests
        # by the FQDN in `ip`, which is the single name for them.
        mac  = try(var.containers[k].dhcp, false) ? local.container_mac[k] : null
        node = v.node_name
        # Connection settings for proxmox_pct_remote (community.proxmox)
        ansible_connection = "community.proxmox.proxmox_pct_remote"
        ansible_pct_vmid   = v.id
        tags               = v.tags
        pool_id            = v.pool_id
      }
    }
    # Regular VMs - using SSH connection
    # DRY: static VMs advertise their vm_id-derived IP; DHCP-first VMs advertise
    # their FQDN (local.vm_address) with a lease-stabilizing deterministic MAC,
    # exactly like the containers block above.
    vms = {
      for k, v in module.vms.vm_details : k => {
        vmid               = v.id
        hostname           = v.name
        ip                 = local.vm_address[k]
        mac                = try(var.vms[k].dhcp, false) ? local.vm_mac[k] : null
        node               = v.node_name
        ansible_connection = try(var.vms[k].ansible_connection, "ssh")
        # Whether the guest is expected to be running. A guest only an operator
        # may power on publishes started = false, so a converge can skip it
        # instead of failing against a host that is deliberately switched off.
        # Reading these here is also what keeps them declared. They are plain
        # attribute reads, not `try()`, so dropping either from var.vms breaks
        # the PLAN instead of silently reverting every guest to the default.
        # `tofu validate` still passes in that state - checked - so the guard
        # that actually bites is the contract test, which asserts both through
        # this output.
        on_boot = var.vms[k].on_boot
        started = var.vms[k].started
        tags    = v.tags
        pool_id = v.pool_id
      }
    }
    # Docker VMs - filtered subset of VMs with "docker" tag
    docker_vms = {
      for k, v in module.vms.vm_details : k => {
        vmid               = v.id
        hostname           = v.name
        ip                 = local.vm_address[k]
        mac                = try(var.vms[k].dhcp, false) ? local.vm_mac[k] : null
        node               = v.node_name
        ansible_connection = "ssh"
        tags               = v.tags
        pool_id            = v.pool_id
      } if contains(try(v.tags, []), "docker")
    }
    # Splunk VM - dedicated Docker host with SSH connection
    splunk_vm = {
      splunk = {
        vmid               = module.splunk_vm.vm_id
        hostname           = module.splunk_vm.name
        ip                 = module.splunk_vm.ip_address # CIDR already stripped in module output
        node               = var.proxmox_node
        ansible_connection = "ssh"
      }
    }
    # Splunk tiered storage - one {datastore_id, disk_interface, size_gb} per tier
    # (fast-splunk hot/warm, bulk-splunk cold). Kept as its own top-level key
    # rather than nested under splunk_vm, which is typed against the shared vm
    # schema. ansible-splunk maps its volume stanzas onto these disks.
    splunk_storage = {
      for tier, d in module.splunk_vm.tiered_disks : tier => {
        datastore_id   = d.datastore_id
        disk_interface = d.interface
        size_gb        = d.size
      }
    }
    # Pipeline constants - service and syslog port definitions
    constants = local.pipeline_constants
    # Traefik ingress route table - one {name, ip, port} per fronted service UI.
    # The ansible-proxmox-apps traefik + technitium_dns roles derive their routers
    # and DNS aliases from this single source instead of hand-listing hosts.
    ingress = local.ingress
    # Ingress HA: the keepalived VRRP virtual IP every fronted service DNS record
    # points at, and the list of ingress-instance addresses (keepalived
    # unicast_peer members). Empty vip + <2 hosts => the keepalived role no-ops,
    # so a single-ingress or partial deployment stays valid.
    ingress_vip   = local.ingress_vip
    ingress_hosts = local.ingress_hosts
    # Host-level NAS service config - consumed by ansible-proxmox to provision ZFS dataset + Samba
    host_services = var.host_services
    # Cluster node inventory (non-secret identity) - ansible-proxmox targets hosts and
    # skips nodes where commissioned = false.
    nodes = var.nodes
    # Per-node ZFS storage to provision (pools/datasets/quotas) - ansible-proxmox creates
    # and registers these; Terraform only references the datastore by id on disks.
    node_storage = var.node_storage
    # Domain for FQDN resolution (e.g., example.com)
    domain = var.domain
    # Base LXC appliance template every container is created from. Published so
    # ansible-proxmox can ensure it is present on each node's local storage
    # instead of re-declaring the filename in its own defaults. Both sides read
    # deployment.json through this key, so bumping the base image is one edit
    # there rather than two edits kept in sync by a comment.
    ct_template = var.proxmox_ct_template_debian
  }
}

# The inherited AWS provider targets homelab RustFS with ephemeral OpenBao
# credentials configured by the Terrakube root workspace.
# Publish point. The object updates only when the inventory content changes, and
# only when this resource is in scope — a `-target` apply that excludes it does
# not republish a partial inventory.
resource "aws_s3_object" "ansible_inventory" {
  bucket       = var.inventory_bucket
  key          = var.inventory_key
  content      = jsonencode(local.ansible_inventory)
  content_type = "application/json"

  # Publish gate: a malformed inventory must fail the apply BEFORE this object is
  # written. There is no after-hook schema check anymore (scripts/sync-inventory.sh
  # was retired with Terragrunt); these preconditions are the only gate, encoding
  # the same required-key contract as the ansible-proxmox-apps JSON schema
  # (tests/inventory_load/tofu_inventory.schema.json) directly in HCL so they run
  # at plan/apply time, before any S3 write.
  #
  # NOTE: `domain` is deliberately NOT asserted here. An empty domain is a
  # supported state in this module — locals.tf falls back to a bare hostname when
  # var.domain == "" (and `tofu test` exercises that default). The downstream
  # requirement that domain be set for the Ansible per-node ansible_host lives in
  # the ansible-proxmox-apps loader (load_tofu.yml), which fails loud there.
  # `nodes` and `node_storage` need no shape precondition beyond their HCL type
  # (map(object(...))) — the schema only requires the key exist, with no
  # minimum-size or format constraint, and both variables default to `{}`.
  lifecycle {
    precondition {
      condition = alltrue([
        for k, c in local.ansible_inventory.containers :
        c.ip != null && c.ip != "" &&
        c.node != null && c.node != "" &&
        c.hostname != null && c.hostname != "" &&
        c.vmid != null
      ])
      error_message = "One or more containers have an empty ip/node/hostname/vmid in the inventory — the Ansible connection target and DNS A-records derive from these. Inspect module.containers output and deployment.json."
    }
    precondition {
      # ansible-proxmox downloads this exact filename onto every node's local
      # storage. Publishing an empty string would make it silently ensure
      # nothing, and container creation then fails later with "volume
      # local:vztmpl/ does not exist" on whichever node is next rebuilt.
      condition     = try(local.ansible_inventory.ct_template, "") != ""
      error_message = "ct_template is empty — ansible-proxmox ensures this template on each node's local storage and container creation references it by name. Set proxmox_ct_template_debian in deployment.json."
    }
    precondition {
      condition = alltrue([
        for k, v in local.ansible_inventory.vms :
        v.ip != null && v.ip != "" &&
        v.node != null && v.node != "" &&
        v.hostname != null && v.hostname != "" &&
        v.vmid != null &&
        contains(["ssh", "winrm"], v.ansible_connection)
      ])
      error_message = "One or more VMs have an empty ip/node/hostname/vmid or an unsupported ansible_connection in the inventory. Inspect module.vms output and deployment.json."
    }
    precondition {
      condition = alltrue([
        for k, v in local.ansible_inventory.docker_vms :
        v.ip != null && v.ip != "" &&
        v.node != null && v.node != "" &&
        v.hostname != null && v.hostname != "" &&
        v.vmid != null
      ])
      error_message = "One or more docker VMs have an empty ip/node/hostname/vmid in the inventory. Inspect module.vms output and the docker-tag filter."
    }
    precondition {
      condition = (
        length(local.ansible_inventory.splunk_vm) > 0 &&
        alltrue([
          for k, v in local.ansible_inventory.splunk_vm :
          v.ip != null && v.ip != "" &&
          v.node != null && v.node != "" &&
          v.hostname != null && v.hostname != "" &&
          v.vmid != null &&
          v.ansible_connection == "ssh"
        ])
      )
      error_message = "splunk_vm is empty or malformed — the schema requires at least one entry with ip/node/hostname/vmid set and ansible_connection = \"ssh\". Inspect module.splunk_vm output."
    }
    precondition {
      condition = alltrue([
        for tier in ["fast", "bulk"] :
        can(local.ansible_inventory.splunk_storage[tier]) &&
        try(local.ansible_inventory.splunk_storage[tier].datastore_id, "") != "" &&
        try(local.ansible_inventory.splunk_storage[tier].disk_interface, "") != ""
      ])
      error_message = "splunk_storage must define both the fast and bulk tiers, each with a non-empty datastore_id and disk_interface. Inspect module.splunk_vm.tiered_disks and the tiered_disks wiring in modules/proxmox-stack/main.tf."
    }
    precondition {
      condition = alltrue([
        for k in [
          "service_ports", "syslog_ports", "syslog_port_map", "netflow_ports",
          "notification_ports", "vector_db_ports", "memory_ports", "media_ports",
          "ai_log_ports", "ai_log_routing", "serving",
        ] : can(local.ansible_inventory.constants[k])
      ])
      error_message = "pipeline_constants is missing one or more required keys (service_ports, syslog_ports, syslog_port_map, netflow_ports, notification_ports, vector_db_ports, memory_ports, media_ports, ai_log_ports, ai_log_routing, serving). Inspect constants.tf."
    }
    precondition {
      condition = alltrue([
        for e in local.ansible_inventory.ingress :
        try(e.name, "") != "" && try(e.port, 0) > 0 && (
          try(e.ip, "") != "" ||
          try(length(e.backends) > 0, false)
        )
      ])
      error_message = "One or more ingress entries are malformed — each needs a name, a port > 0, and either a non-empty ip (single-backend route) or a non-empty backends pool (load-balanced route, apex or not — e.g. the openbao HA pool). Inspect ingress.tf."
    }
  }
}
