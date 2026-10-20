# Migration defaults on when a replica target exists; explicit values win.
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
    replicated = {
      vm_id                 = 605042
      node_name             = "node-a"
      hostname              = "replicated"
      template_file_id      = "local:vztmpl/example.tar.zst"
      ha_replication_target = "node-b"
    }
    pinned = {
      vm_id                 = 605043
      node_name             = "node-a"
      hostname              = "pinned"
      template_file_id      = "local:vztmpl/example.tar.zst"
      ha_replication_target = "node-b"
      migrate               = false
    }
    engine_replicated = {
      vm_id                   = 605044
      node_name               = "node-a"
      hostname                = "engine-replicated"
      template_file_id        = "local:vztmpl/example.tar.zst"
      llm_gpu_engine_identity = "llama_cpp"
      ha_replication_target   = "node-b"
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
    error_message = "Containers without a replica target must default to migrate=false."
  }
}

run "replica_target_enables_migration_by_default" {
  command = plan

  assert {
    condition     = proxmox_virtual_environment_container.containers["replicated"].migrate == true
    error_message = "A container with a replica target must default to migrate=true."
  }
}

run "explicit_false_overrides_replica_target" {
  command = plan

  assert {
    condition     = proxmox_virtual_environment_container.containers["pinned"].migrate == false
    error_message = "An explicit migrate=false must override the replica-target default."
  }
}

run "engine_container_replica_target_enables_migration" {
  command = plan

  assert {
    condition     = proxmox_virtual_environment_container.engine_containers["engine_replicated"].migrate == true
    error_message = "Engine containers with a replica target must default to migrate=true."
  }
}
