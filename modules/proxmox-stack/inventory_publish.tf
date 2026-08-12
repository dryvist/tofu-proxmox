# Native publish of the Ansible inventory to the homelab RustFS service.
#
# `tofu apply` is the publish boundary: the aws_s3_object below uploads the
# inventory whenever its content changes — no shell script, no `aws` CLI. Any
# consumer (CI via OIDC, cloud agents, ansible) fetches this object with scoped
# read creds, with no checkout and no terraform toolchain.
#
# The AWS provider uses the same ambient credential chain as the S3 *state*
# backend (native root configuration) — no static keys here.

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
      # A VDI guest's persistent routes are (destination, gateway) pairs, and the
      # gateway half cannot be discovered inside the guest — a VPN client owns the
      # default route by the time the route matters. A null gateway here would
      # publish destinations with nothing to point them at, and the role would
      # skip silently, which is exactly the shape of failure this repo keeps
      # getting bitten by.
      #
      # This guard first shipped asserting that a VDI guest was STATICALLY
      # addressed, because the published gateway was the cloud-init one, which is
      # null on a lease. That was backwards: the estate is DHCP-first by design,
      # so it rejected every real VDI guest. The gateway now derives from the
      # guest's VLAN and holds either way; what remains worth asserting is that
      # something is actually published.
      condition = length(local.ansible_inventory.vdi_preserved_cidrs) == 0 || alltrue([
        for k, v in local.ansible_inventory.vms :
        v.gateway != null && v.gateway != "" if contains(try(v.tags, []), "vdi")
      ])
      error_message = "A guest tagged \"vdi\" has no gateway published, but vdi_preserved_cidrs is non-empty — its LAN routes cannot be built. Check that the guest's vlan resolves in network_cidrs; the gateway is the .1 of that subnet."
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
          "notification_ports", "vector_db_ports", "memory_ports", "extract_ports",
          "media_ports", "ai_log_ports", "ai_log_routing", "serving",
        ] : can(local.ansible_inventory.constants[k])
      ])
      error_message = "pipeline_constants is missing one or more required keys (service_ports, syslog_ports, syslog_port_map, netflow_ports, notification_ports, vector_db_ports, memory_ports, extract_ports, media_ports, ai_log_ports, ai_log_routing, serving). Inspect constants.tf."
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
