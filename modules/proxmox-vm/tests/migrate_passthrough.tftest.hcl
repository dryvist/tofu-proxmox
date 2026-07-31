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
  proxmox_ssh_username    = "root"
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
  }
}

run "migrate_reaches_the_resource_when_declared" {
  command = plan

  assert {
    condition     = proxmox_virtual_environment_vm.vms["mover"].migrate == true
    error_message = "migrate=true did not reach the VM resource — a node_name change on this guest would destroy and recreate it instead of migrating."
  }
}

# The negative control. Without this, the test above would still pass if the
# module hard-coded `migrate = true`, which would silently turn every node
# reassignment into a migration — the opposite and more dangerous default.
run "migrate_defaults_off_when_not_declared" {
  command = plan

  assert {
    condition     = proxmox_virtual_environment_vm.vms["stayer"].migrate == false
    error_message = "migrate defaulted to something other than false — node reassignment must not migrate a guest unless the deployment object explicitly asks for it."
  }
}
