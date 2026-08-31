# The `containers` map of the published Ansible inventory.
#
# Hoisted out of inventory_assembly.tf for the same reason that file was itself
# split out of inventory_publish.tf: the assembly reached the repository's 12 KB
# per-file gate, and this was its largest single block. The split is purely
# physical — a local is module-scoped regardless of which file declares it — and
# it keeps a diff to the container shape readable on its own.
#
# Consumed by local.ansible_inventory in inventory_assembly.tf.

locals {
  inventory_containers = {
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
      # The node holding this guest's replica, published so the HA layer can
      # derive its relocation target from the desired state instead of carrying
      # a node name of its own. A PLAIN read, not try(): reading it here is what
      # keeps the attribute DECLARED, and an undeclared attribute is silently
      # stripped from the desired state rather than erroring.
      ha_replication_target = var.containers[k].ha_replication_target
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
      # the vms block, reading them here is what keeps them DECLARED. An
      # undeclared attribute is silently stripped from the desired state, so a
      # try() would turn a dropped field into a null that looks like "this guest
      # has no sizing" rather than breaking the plan.
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
      # coalesce, not a plain read: datastore_id is optional and null for every
      # guest taking the node default, so a raw read would publish null for most
      # guests. Resolves the EFFECTIVE datastore exactly as
      # modules/proxmox-container/main.tf does when it creates the disk.
      #
      # A VM's equivalent in the vms block is a PLAIN read, because
      # boot_disk.datastore_id carries a default and is therefore never null.
      datastore = coalesce(var.containers[k].root_disk.datastore_id, var.datastore_default)
    }
  }
}
