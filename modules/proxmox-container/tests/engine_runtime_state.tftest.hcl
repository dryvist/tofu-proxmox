# Runtime started state is managed only for explicitly engine-identified GPU
# containers. The ordinary fleet keeps its existing ignored runtime state.
mock_provider "proxmox" {}

variables {
  domain            = "example.test"
  environment       = "test"
  default_datastore = "local-zfs"

  containers = {
    ordinary = {
      vm_id            = 705000
      node_name        = "proxmox-1"
      hostname         = "ordinary"
      template_file_id = "local:vztmpl/example.tar.zst"
    }
    llama_cpp = {
      vm_id                   = 705001
      node_name               = "proxmox-1"
      hostname                = "engine-a"
      template_file_id        = "local:vztmpl/example.tar.zst"
      llm_gpu_engine_identity = "llama_cpp"
      start_on_boot           = false
      started                 = false
    }
    vllm = {
      vm_id                   = 705002
      node_name               = "proxmox-1"
      hostname                = "engine-b"
      template_file_id        = "local:vztmpl/example.tar.zst"
      llm_gpu_engine_identity = "vllm"
      start_on_boot           = false
      started                 = false
    }
  }
}

run "ordinary_runtime_is_ignored_and_engine_pair_is_explicit" {
  command = plan

  assert {
    condition     = contains(keys(proxmox_virtual_environment_container.containers), "ordinary")
    error_message = "ordinary containers must remain on the existing lifecycle resource."
  }

  assert {
    condition     = !contains(keys(proxmox_virtual_environment_container.engine_containers), "ordinary")
    error_message = "ordinary containers must not opt into managed runtime state."
  }

  assert {
    condition = (
      length(proxmox_virtual_environment_container.engine_containers) == 2 &&
      contains(keys(proxmox_virtual_environment_container.engine_containers), "llama_cpp") &&
      contains(keys(proxmox_virtual_environment_container.engine_containers), "vllm")
    )
    error_message = "only engine-identified containers belong on the managed runtime resource."
  }

  assert {
    condition = alltrue([
      for container in values(proxmox_virtual_environment_container.engine_containers) :
      container.started == false && container.start_on_boot == false
    ])
    error_message = "the prepared engine pair must remain stopped and disabled at boot."
  }

  assert {
    condition = (
      proxmox_virtual_environment_container.containers["ordinary"].started == null &&
      proxmox_virtual_environment_container.engine_containers["llama_cpp"].started == false &&
      proxmox_virtual_environment_container.engine_containers["vllm"].started == false
    )
    error_message = "ordinary runtime state stays provider-computed while the engine pair runtime is explicit."
  }
}
