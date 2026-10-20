# Does `migrate` actually reach the VM resource?
#
# This exists because the failure mode is SILENT. An object type constraint
# drops attributes it does not declare rather than erroring, so a `migrate`
# written into deployment.json but missing from this module's schema simply
# vanishes — and the only symptom is a plan that says "must be replaced"
# instead of migrating, i.e. destroying a guest's disks. Nothing in fmt,
# validate, or a type check catches that.
#
# So the assertions read the attribute ON THE RESOURCE, not the variable. A
# test that asserted `var.vms[...].migrate` would still pass with the
# `migrate = each.value.migrate` line deleted from main.tf, which is exactly
# the regression worth catching.

mock_provider "proxmox" {}

variables {
  domain                  = "example.test"
  environment             = "test"
  default_datastore       = "local-zfs"
  proxmox_user            = "root"
  proxmox_ssh_private_key = "not-a-real-key"

  vms = {
    mover = {
      vm_id     = 250
      name      = "mover"
      node_name = "proxmox-3"
      migrate   = true
      user_account = {
        username = "test"
        password = "test"
        keys     = []
      }
    }
    stayer = {
      vm_id     = 251
      name      = "stayer"
      node_name = "proxmox-1"
      user_account = {
        username = "test"
        password = "test"
        keys     = []
      }
    }
    replicated = {
      vm_id                 = 252
      name                  = "replicated"
      node_name             = "node-a"
      ha_replication_target = "node-b"
      user_account = {
        username = "test"
        password = "test"
        keys     = []
      }
    }
    pinned = {
      vm_id                 = 253
      name                  = "pinned"
      node_name             = "node-a"
      ha_replication_target = "node-b"
      migrate               = false
      user_account = {
        username = "test"
        password = "test"
        keys     = []
      }
    }
  }
}

run "migrate_reaches_the_resource_when_declared" {
  command = plan

  assert {
    condition     = proxmox_virtual_environment_vm.vms["mover"].migrate == true
    error_message = "migrate=true did not reach the VM resource — a node_name change on this guest would destroy and recreate it instead of migrating."
  }
}

# The negative control: a VM without a replica target stays on the replacement
# default, while HA-replicated VMs migrate unless an explicit value says otherwise.
run "migrate_defaults_off_when_not_declared" {
  command = plan

  assert {
    condition     = proxmox_virtual_environment_vm.vms["stayer"].migrate == false
    error_message = "A VM without a replica target must default to migrate=false."
  }
}

run "replica_target_enables_migration_by_default" {
  command = plan

  assert {
    condition     = proxmox_virtual_environment_vm.vms["replicated"].migrate == true
    error_message = "A VM with a replica target must default to migrate=true."
  }
}

run "explicit_false_overrides_replica_target" {
  command = plan

  assert {
    condition     = proxmox_virtual_environment_vm.vms["pinned"].migrate == false
    error_message = "An explicit migrate=false must override the replica-target default."
  }
}
