# Assembly of the Ansible inventory value.
#
# Split out of inventory_publish.tf, which holds the aws_s3_object that uploads
# it. The two were one file until the assembly grew past the repository's 12 KB
# per-file gate; the split is purely physical, since a local is module-scoped
# regardless of which file declares it. Keeping the assembly separate from the
# publish boundary also keeps a diff to the inventory *shape* readable on its
# own.
#
# Consumed by output.ansible_inventory and by aws_s3_object.ansible_inventory
# (a resource cannot reference an output, which is why this is a local).

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
        # The guest's live MAC, published for EVERY container.
        #
        # DHCP-first guests carry the deterministic MAC from local.container_mac,
        # which keeps the lease — and therefore the address and the lease-table DNS
        # name — stable across a rebuild. It is NOT a reservation key: this
        # inventory no longer publishes a reserved address, because a leased
        # guest's address exists only in the lease. Consumers address these guests
        # by the FQDN in `ip`, which is the single name for them.
        #
        # Static guests used to publish null here, which left them unnameable
        # downstream: a static guest never sends DHCP option 12, so the network
        # controller learns no hostname and lists it by MAC. A client alias keyed
        # on the MAC is the only fix, and it needs this field populated. The value
        # is READ from the provider, never assigned, so no live guest is touched.
        mac  = v.mac_address
        node = v.node_name
        # Connection settings for proxmox_pct_remote (community.proxmox)
        ansible_connection = "community.proxmox.proxmox_pct_remote"
        ansible_pct_vmid   = v.id
        tags               = v.tags
        pool_id            = v.pool_id
        # Declared sizing, published so Nautobot can be the SSoT for it.
        # VirtualMachine.vcpus/memory/disk were null for every guest because
        # nothing carried these downstream — the desired state has them, the
        # inventory did not, so the seed bundle could not either.
        #
        # Plain attribute reads, not try(): exactly like the `started` field in
        # the vms block below, reading them here is what keeps them DECLARED.
        # An undeclared attribute is silently stripped from the desired state,
        # so a try() would turn a dropped field into a null that looks like
        # "this guest has no sizing" rather than breaking the plan.
        #
        # Units are the guest's own: cores as a count, memory in MB, disk in GB.
        # Nautobot's VirtualMachine uses MB for memory and GB for disk, so these
        # map across without conversion — do not "helpfully" rescale them.
        cpu_cores = var.containers[k].cpu_cores
        memory_mb = var.containers[k].memory_dedicated
        disk_gb   = var.containers[k].root_disk.size
        # WHERE the root disk lives, not just how big it is. A consumer that
        # snapshots a guest's dataset needs its pool; without this it must
        # hardcode one, which stops being true the moment the guest moves tier
        # -- silently, because a move retains the source volume.
        #
        # coalesce, not a plain read: datastore_id is optional and null for
        # every guest taking the node default, so a raw read would publish null
        # for most guests. Resolves the EFFECTIVE datastore exactly as
        # modules/proxmox-container/main.tf does when it creates the disk.
        datastore = coalesce(var.containers[k].root_disk.datastore_id, var.datastore_default)
      }
    }
    # Regular VMs - using SSH connection
    # DRY: static VMs advertise their vm_id-derived IP; DHCP-first VMs advertise
    # their FQDN (local.vm_address) with a lease-stabilizing deterministic MAC,
    # exactly like the containers block above — and, also like that block, every
    # VM publishes its MAC so a static one can still be named downstream.
    vms = {
      for k, v in module.vms.vm_details : k => {
        vmid               = v.id
        hostname           = v.name
        ip                 = local.vm_address[k]
        mac                = v.mac_address
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
        # Same sizing contract as the containers block above, for the same
        # reason: Nautobot models vcpus/memory/disk natively and a guest without
        # them reads null. Publishing it for containers ONLY left the actual VMs
        # — the guests the field name refers to — still blank.
        #
        # boot_disk.size rather than root_disk.size: a VM's system disk is
        # boot_disk here, and additional_disks are deliberately excluded because
        # Nautobot's `disk` is a single number, not a sum. Recording a total
        # would silently disagree with what the guest calls its disk.
        cpu_cores = var.vms[k].cpu_cores
        memory_mb = var.vms[k].memory_dedicated
        disk_gb   = var.vms[k].boot_disk.size
        # The guest's own LAN gateway. Published because a guest running a VPN
        # client cannot discover it at converge time: the client owns the
        # default route by then, so "the current gateway" is the tunnel's.
        #
        # vm_lan_gateway, NOT vm_gateway: the latter is the cloud-init value and
        # is null for DHCP-first guests, which is nearly the whole estate. The
        # VLAN's gateway is well defined either way and is what DHCP hands out.
        gateway = local.vm_lan_gateway[k]
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
        mac                = v.mac_address
        node               = v.node_name
        ansible_connection = "ssh"
        tags               = v.tags
        pool_id            = v.pool_id
        # docker_vms is a FILTERED VIEW of the same vms map, so it needs the
        # same sizing reads -- a guest does not stop having a size because it
        # is republished under a second key.
        cpu_cores = var.vms[k].cpu_cores
        memory_mb = var.vms[k].memory_dedicated
        disk_gb   = var.vms[k].boot_disk.size
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
        # Sized from its own variables -- this guest is built by a dedicated
        # module, not from var.vms. disk_gb is the BOOT disk: the tiered data
        # disks are published separately under splunk_storage, and Nautobot's
        # `disk` is a single number, so summing them would disagree with what
        # the guest calls its disk.
        cpu_cores = var.splunk_cpu_cores
        memory_mb = var.splunk_memory
        disk_gb   = var.splunk_boot_disk_size
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
    # Cluster node inventory (non-secret identity) - ansible-proxmox targets hosts and
    # skips nodes where commissioned = false.
    nodes = var.nodes
    # Per-node ZFS storage to provision (pools/datasets/quotas) - ansible-proxmox creates
    # and registers these; Terraform only references the datastore by id on disks.
    node_storage = var.node_storage
    # Subnets a VDI guest keeps reaching over its own LAN rather than through a
    # VPN client running inside it. Resolved from var.vdi_preserved_vlans against
    # network_cidrs so no subnet is ever written down twice; see that variable for
    # why this is a short opt-in list and not every VLAN. Empty = feature off.
    #
    # nonsensitive() is the same call locals-vm-network.tf already makes for every
    # guest address derived from this map: the inventory publishes those addresses,
    # so the subnets they sit in are not independently secret. It is scoped to the
    # listed keys, so the rest of network_cidrs stays out of the artifact.
    vdi_preserved_cidrs = [
      for vlan in var.vdi_preserved_vlans : nonsensitive(var.network_cidrs[vlan])
    ]
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
