# Do `on_boot` and `started` actually reach the VM resource?
#
# Same silent-failure shape as migrate_passthrough.tftest.hcl, and this one has
# already bitten: `on_boot` was wired as `try(each.value.on_boot, true)`, which
# swallows a missing attribute instead of failing. The calling stack's object
# type did not declare on_boot at all, so every guest was pinned to `true` no
# matter what the desired state asked for, and nothing in fmt, validate or the
# type system said a word. `try()` is why it stayed invisible.
#
# The two attributes are independent and BOTH are needed for a guest the
# operator alone may power on:
#   on_boot = false  - the node booting does not start it
#   started = false  - the apply that creates it does not start it
# Setting only on_boot still leaves terraform powering the guest on at create.
#
# Assertions read the attribute ON THE RESOURCE, not the variable: a test
# against `var.vms[...]` would still pass with the wiring deleted from main.tf.

mock_provider "proxmox" {}

variables {
  domain                  = "example.test"
  environment             = "test"
  default_datastore       = "local-zfs"
  proxmox_ssh_username    = "root"
  proxmox_ssh_private_key = "not-a-real-key"

  vms = {
    manual = {
      vm_id     = 260
      name      = "manual"
      node_name = "proxmox-1"
      on_boot   = false
      started   = false
      user_account = {
        username = "test"
        password = "test"
        keys     = []
      }
    }
    automatic = {
      vm_id     = 261
      name      = "automatic"
      node_name = "proxmox-1"
      user_account = {
        username = "test"
        password = "test"
        keys     = []
      }
    }
  }
}

run "on_boot_false_reaches_the_resource" {
  command = plan

  assert {
    condition     = proxmox_virtual_environment_vm.vms["manual"].on_boot == false
    error_message = "on_boot=false did not reach the VM resource — the guest would start whenever its node boots, against the desired state."
  }
}

run "started_false_reaches_the_resource" {
  command = plan

  assert {
    condition     = proxmox_virtual_environment_vm.vms["manual"].started == false
    error_message = "started=false did not reach the VM resource — the apply that creates this guest would power it on, and only a human is supposed to do that."
  }
}

# Negative controls. Without these, both tests above would still pass if the
# module hard-coded `false`, which would stop every other guest in the estate
# from ever coming back after a node reboot — far worse than the bug being
# guarded against here.
run "startup_defaults_stay_on_when_not_declared" {
  command = plan

  assert {
    condition     = proxmox_virtual_environment_vm.vms["automatic"].on_boot == true
    error_message = "on_boot defaulted to something other than true — an undeclared guest must still start with its node."
  }

  assert {
    condition     = proxmox_virtual_environment_vm.vms["automatic"].started == true
    error_message = "started defaulted to something other than true — an undeclared guest must still be running once created."
  }
}
