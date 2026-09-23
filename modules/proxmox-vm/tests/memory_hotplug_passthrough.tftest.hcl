# Does memory_hotplug actually reach the VM resource's top-level `hotplug`
# attribute and the cpu block's `numa` flag? A memory_dedicated raise only
# skips the reboot when both are set (PVE requirement — memory hotplug needs
# NUMA on) — see the field's own comment in variables.tf.
#
# Assertions read the attribute ON THE RESOURCE, not the variable: a test
# against `var.vms[...]` would still pass with the wiring deleted from main.tf.

mock_provider "proxmox" {}

variables {
  domain                  = "example.test"
  environment             = "test"
  default_datastore       = "local-zfs"
  proxmox_user            = "root"
  proxmox_ssh_private_key = "not-a-real-key"

  vms = {
    hotpluggable = {
      vm_id          = 264
      name           = "hotpluggable"
      node_name      = "proxmox-1"
      memory_hotplug = true
      user_account = {
        username = "test"
        password = "test"
        keys     = []
      }
    }
    plain = {
      vm_id     = 265
      name      = "plain"
      node_name = "proxmox-1"
      user_account = {
        username = "test"
        password = "test"
        keys     = []
      }
    }
  }
}

run "memory_hotplug_true_sets_hotplug_and_numa" {
  command = plan

  assert {
    condition     = proxmox_virtual_environment_vm.vms["hotpluggable"].hotplug == "network,disk,usb,memory,cpu"
    error_message = "memory_hotplug=true did not reach the VM resource's hotplug attribute."
  }

  assert {
    condition     = proxmox_virtual_environment_vm.vms["hotpluggable"].cpu[0].numa == true
    error_message = "memory_hotplug=true did not enable NUMA, memory hotplug's own PVE prerequisite."
  }
}

# Negative control: an undeclared memory_hotplug must not enable NUMA, or
# every existing guest picks up an unrequested hotplug prerequisite.
# (`hotplug` itself is Optional+Computed in the provider schema — omitted in
# config it becomes unknown-until-apply, so mock_provider fills a random
# value under `plan` rather than the real PVE default; only the concrete
# `numa` default is assertable here.)
run "memory_hotplug_default_leaves_numa_off" {
  command = plan

  assert {
    condition     = proxmox_virtual_environment_vm.vms["plain"].cpu[0].numa == false
    error_message = "NUMA was enabled despite memory_hotplug defaulting to false."
  }
}
