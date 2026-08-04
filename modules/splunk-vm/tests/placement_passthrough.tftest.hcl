# Do `cpu_type` and `migrate` actually reach the Splunk VM resource?
#
# Same silent failure mode as modules/proxmox-vm/tests/migrate_passthrough:
# nothing in fmt, validate, or a type check notices a variable that is declared
# but never wired to the resource. The consequence here is worse than a stalled
# migration — this VM carries the index volumes, so a node_name change that
# falls back to replace-instead-of-migrate destroys them.
#
# Assertions read the attributes ON THE RESOURCE, not the variables, so deleting
# `type = var.cpu_type` or `migrate = var.migrate` from main.tf fails the test.

# The cloud-init file id is mocked explicitly: the provider validates that
# user_data_file_id looks like "datastore:snippets/name", and a mock's
# auto-generated random id does not, so the plan fails on shape rather than on
# anything this test is about.
mock_provider "proxmox" {
  mock_resource "proxmox_virtual_environment_file" {
    defaults = {
      id = "local:snippets/splunk-test.yaml"
    }
  }
}

variables {
  vm_id      = 200
  name       = "splunk-test"
  node_name  = "proxmox-3"
  ip_address = "198.51.100.99/24"
  gateway    = "198.51.100.1"
  cpu_type   = "x86-64-v2"
  migrate    = true
}

run "cpu_type_and_migrate_reach_the_resource" {
  command = plan

  assert {
    condition     = proxmox_virtual_environment_vm.splunk_vm.cpu[0].type == "x86-64-v2"
    error_message = "cpu_type did not reach the VM resource — the guest would stay pinned to the host CPU model and could not migrate across CPU vendors."
  }

  assert {
    condition     = proxmox_virtual_environment_vm.splunk_vm.migrate == true
    error_message = "migrate=true did not reach the VM resource — a node_name change would destroy and recreate this VM, taking the index volumes with it."
  }
}

# Negative control: without it, hard-coding either value would still pass above.
# "host" and migrate=false must remain the defaults — a module that migrated by
# default would turn any node reassignment into a live move without anyone
# asking for one.
run "defaults_preserve_current_behaviour" {
  command = plan

  variables {
    cpu_type = "host"
    migrate  = false
  }

  assert {
    condition     = proxmox_virtual_environment_vm.splunk_vm.cpu[0].type == "host"
    error_message = "cpu_type default is no longer \"host\" — that silently changes the CPU model of the existing VM on the next apply."
  }

  assert {
    condition     = proxmox_virtual_environment_vm.splunk_vm.migrate == false
    error_message = "migrate defaulted to something other than false — node reassignment must not migrate this VM unless the deployment object explicitly asks for it."
  }
}
