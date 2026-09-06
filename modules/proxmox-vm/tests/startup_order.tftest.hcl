# Does an explicit `startup_order` actually reach the VM resource, and does
# leaving it unset still produce the VMID-derived order?
#
# The container module gained this override first; the VM module had none at
# all, so a VM's boot position was whatever its VMID happened to imply and
# could not be corrected even deliberately. The derivation encodes tier only by
# accident of the numbering scheme — a guest below 1000 uses its VMID directly,
# everything else uses the thousands prefix — so a legacy three-digit guest
# sorts ahead of every six-digit one.
#
# Assertions read the attribute ON THE RESOURCE, not the variable: a test
# against `var.vms[...]` would still pass with the wiring removed from main.tf.

mock_provider "proxmox" {}

variables {
  domain                  = "example.test"
  environment             = "test"
  default_datastore       = "local-zfs"
  proxmox_ssh_username    = "root"
  proxmox_ssh_private_key = "not-a-real-key"

  vms = {
    # Explicit override, deliberately far from anything the VMID would derive.
    pinned = {
      vm_id         = 421100
      name          = "pinned"
      node_name     = "proxmox-1"
      startup_order = 20
      user_account = {
        username = "test"
        password = "test"
        keys     = []
      }
    }
    # Six-digit VMID, no override: thousands prefix.
    derived_wide = {
      vm_id     = 495100
      name      = "derived-wide"
      node_name = "proxmox-1"
      user_account = {
        username = "test"
        password = "test"
        keys     = []
      }
    }
    # Legacy three-digit VMID, no override: the VMID itself.
    derived_legacy = {
      vm_id     = 240
      name      = "derived-legacy"
      node_name = "proxmox-1"
      user_account = {
        username = "test"
        password = "test"
        keys     = []
      }
    }
  }
}

run "explicit_startup_order_reaches_the_resource" {
  command = plan

  assert {
    condition     = tonumber(proxmox_virtual_environment_vm.vms["pinned"].startup[0].order) == 20
    error_message = "startup_order did not reach the VM resource — the guest would keep its VMID-derived boot position and the declared order would be silently ignored."
  }
}

# Negative controls. Without these the test above would still pass if the
# module hard-coded a constant, which would collapse every guest onto one boot
# order.
run "unset_startup_order_keeps_the_vmid_derivation" {
  command = plan

  assert {
    condition     = tonumber(proxmox_virtual_environment_vm.vms["derived_wide"].startup[0].order) == 495
    error_message = "a six-digit VMID no longer derives its thousands prefix as the boot order; adding the override changed guests that never declared one."
  }

  assert {
    condition     = tonumber(proxmox_virtual_environment_vm.vms["derived_legacy"].startup[0].order) == 240
    error_message = "a legacy three-digit VMID no longer uses its VMID as the boot order; adding the override changed guests that never declared one."
  }
}
