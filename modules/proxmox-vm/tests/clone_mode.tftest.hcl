# Does `clone_template.full` reach the clone block?
#
# Same silent-drop class as migrate_passthrough and startup_passthrough: an
# object type constraint discards an attribute it does not declare, so a
# `full = false` written into deployment.json would simply vanish and every
# clone would quietly be a full one again.
#
# The cost of that regression is disk, and it is not small. A full clone copies
# the template's disk up front — 9-12 GB for a Windows template. Two of them
# once left pve540's 110 GB boot pool with 150 MB to spare, which is how the
# 2026-08-07 pool-exhaustion outage nearly repeated itself.
#
# Assertions read the attribute ON THE RESOURCE. The provider defaults `full`
# to true, so a test that only checked the variable would pass with the
# `full = clone.value.full` line deleted from main.tf.

mock_provider "proxmox" {}

variables {
  domain                  = "example.test"
  environment             = "test"
  default_datastore       = "local-zfs"
  proxmox_ssh_username    = "root"
  proxmox_ssh_private_key = "not-a-real-key"

  vms = {
    linked = {
      vm_id     = 270
      name      = "linked"
      node_name = "proxmox-1"
      clone_template = {
        template_id = 9210
        full        = false
      }
      user_account = {
        username = "test"
        password = "test"
        keys     = []
      }
    }
    thick = {
      vm_id     = 271
      name      = "thick"
      node_name = "proxmox-1"
      clone_template = {
        template_id = 9210
      }
      user_account = {
        username = "test"
        password = "test"
        keys     = []
      }
    }
  }
}

run "linked_clone_reaches_the_resource" {
  command = plan

  assert {
    condition     = proxmox_virtual_environment_vm.vms["linked"].clone[0].full == false
    error_message = "full=false did not reach the clone block — the guest would be cloned thick, copying the whole template disk and risking pool exhaustion."
  }
}

# Negative control. Without it the test above would still pass if the module
# hard-coded `full = false`, which would silently make every clone in the
# estate linked — and a linked clone pins its template forever.
run "clone_defaults_to_full_when_not_declared" {
  command = plan

  assert {
    condition     = proxmox_virtual_environment_vm.vms["thick"].clone[0].full == true
    error_message = "clone.full defaulted to something other than true — a guest must only become a linked clone when the deployment object explicitly asks."
  }
}
