# Does an explicit `startup_order` actually reach the container resource, and
# does leaving it unset still produce the VMID-derived order?
#
# Both halves matter. The derivation encodes tier only by accident of the
# numbering scheme — a guest below 1000 uses its VMID directly, everything else
# uses the thousands prefix — so a legacy three-digit guest sorts ahead of every
# six-digit one and boots before the ingress and the log collectors. The
# override is the fix; a default that quietly changed would reorder the whole
# estate's boot sequence without anything saying so.
#
# Assertions read the attribute ON THE RESOURCE, not the variable: a test
# against `var.containers[...]` would still pass with the wiring removed from
# main.tf.

mock_provider "proxmox" {}

variables {
  domain            = "example.test"
  environment       = "test"
  default_datastore = "local-zfs"

  containers = {
    # Explicit override, deliberately far from anything the VMID would derive.
    pinned = {
      vm_id            = 605020
      node_name        = "proxmox-1"
      hostname         = "pinned"
      template_file_id = "local:vztmpl/example.tar.zst"
      startup_order    = 20
    }
    # Six-digit VMID, no override: thousands prefix.
    derived_wide = {
      vm_id            = 421000
      node_name        = "proxmox-1"
      hostname         = "derived-wide"
      template_file_id = "local:vztmpl/example.tar.zst"
    }
    # Legacy three-digit VMID, no override: the VMID itself.
    derived_legacy = {
      vm_id            = 110
      node_name        = "proxmox-1"
      hostname         = "derived-legacy"
      template_file_id = "local:vztmpl/example.tar.zst"
    }
  }
}

run "explicit_startup_order_reaches_the_resource" {
  command = plan

  assert {
    condition     = tonumber(proxmox_virtual_environment_container.containers["pinned"].startup[0].order) == 20
    error_message = "startup_order did not reach the container resource — the guest would keep its VMID-derived boot position and the declared order would be silently ignored."
  }
}

# Negative controls. Without these the test above would still pass if the module
# hard-coded a constant, which would collapse every guest onto one boot order.
run "unset_startup_order_keeps_the_vmid_derivation" {
  command = plan

  assert {
    condition     = tonumber(proxmox_virtual_environment_container.containers["derived_wide"].startup[0].order) == 421
    error_message = "a six-digit VMID no longer derives its thousands prefix as the boot order; adding the override changed guests that never declared one."
  }

  assert {
    condition     = tonumber(proxmox_virtual_environment_container.containers["derived_legacy"].startup[0].order) == 110
    error_message = "a legacy three-digit VMID no longer uses its VMID as the boot order; adding the override changed guests that never declared one."
  }
}
