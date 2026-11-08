# Does cpu_units actually reach the cpu block's `units` attribute, and does an
# unset cpu_units leave the block exactly as before the field existed?
#
# The provider's cpu.units is Optional+Computed with no default of its own:
# omitted (or null) it stays unknown until apply and carries the node's value.
# Under mock_provider such an unknown fills a random value at plan time, so the
# unset case is asserted through the block's concrete attributes; only an
# explicit cpu_units is numerically assertable.
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
    weighted = {
      vm_id     = 266
      name      = "weighted"
      node_name = "proxmox-1"
      cpu_units = 512
      user_account = {
        username = "test"
        password = "test"
        keys     = []
      }
    }
    plain = {
      vm_id     = 267
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

run "cpu_units_reaches_the_resource" {
  command = plan

  assert {
    condition     = tonumber(proxmox_virtual_environment_vm.vms["weighted"].cpu[0].units) == 512
    error_message = "cpu_units did not reach the cpu block's units attribute — the declared weight would be silently ignored."
  }
}

# Negative control: an entry without cpu_units renders the same cpu block as
# before the field existed — cores, type, hotplugged and numa unchanged, units
# left to the provider (unknown-until-apply, never forced by the module).
run "unset_cpu_units_renders_the_previous_block" {
  command = plan

  assert {
    condition     = proxmox_virtual_environment_vm.vms["plain"].cpu[0].cores == 2
    error_message = "the default cpu_cores changed for guests that never declared cpu_units."
  }

  assert {
    condition     = proxmox_virtual_environment_vm.vms["plain"].cpu[0].type == "host"
    error_message = "the default cpu_type changed for guests that never declared cpu_units."
  }

  assert {
    condition     = proxmox_virtual_environment_vm.vms["plain"].cpu[0].hotplugged == 0
    error_message = "hotplugged changed for guests that never declared cpu_units."
  }

  assert {
    condition     = proxmox_virtual_environment_vm.vms["plain"].cpu[0].numa == false
    error_message = "NUMA was enabled for guests that never declared cpu_units."
  }
}

# Proxmox's cgroup v2 weight range is 1-10000; out-of-range values are rejected
# at the variable, before any provider call.
run "cpu_units_out_of_range_fails_validation" {
  command = plan

  variables {
    vms = {
      bad = {
        vm_id     = 268
        name      = "bad"
        node_name = "proxmox-1"
        cpu_units = 10001
        user_account = {
          username = "test"
          password = "test"
          keys     = []
        }
      }
    }
  }

  expect_failures = [var.vms]
}
