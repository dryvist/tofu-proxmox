# The container provider's migration setting reaches each resource and stays
# disabled unless an input opts in.
mock_provider "proxmox" {}

variables {
  domain            = "example.test"
  environment       = "test"
  default_datastore = "local-zfs"

  containers = {
    movable = {
      vm_id            = 605040
      node_name        = "proxmox-1"
      hostname         = "movable"
      template_file_id = "local:vztmpl/example.tar.zst"
      migrate          = true
    }
    steady = {
      vm_id            = 605041
      node_name        = "proxmox-1"
      hostname         = "steady"
      template_file_id = "local:vztmpl/example.tar.zst"
    }
  }
}

run "explicit_migration_reaches_the_resource" {
  command = plan

  assert {
    condition     = proxmox_virtual_environment_container.containers["movable"].migrate == true
    error_message = "The migrate input did not reach the container resource."
  }
}

run "migration_is_disabled_by_default" {
  command = plan

  assert {
    condition     = proxmox_virtual_environment_container.containers["steady"].migrate == false
    error_message = "Containers without migrate=true must keep the provider default."
  }
}
