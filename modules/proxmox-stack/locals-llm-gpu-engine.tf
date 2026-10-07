locals {
  llm_gpu_engine_declared_members = {
    for name, container in var.containers : name => container
    if container.llm_gpu_engine_identity != null
  }

  llm_gpu_engine_pair_present = length(local.llm_gpu_engine_declared_members) == 2

  llm_gpu_engine_pair_node = local.llm_gpu_engine_pair_present ? try(one(distinct([
    for container in values(local.llm_gpu_engine_declared_members) : container.node_name
  ])), null) : null

  # The current serving LXC shares the same physical GPU as the replacement
  # pair. Keep its resource address and volumes intact, but publish the runtime
  # handoff only once the pair is declared. The host role performs the graceful
  # stop after the replacement shell exists and before GPU passthrough restarts
  # it. Scope by node so an unrelated llm-gpu guest is never selected.
  llm_gpu_engine_legacy_members = {
    for name, container in var.containers : name => container
    if local.llm_gpu_engine_pair_present &&
    container.llm_gpu_engine_identity == null &&
    contains(container.tags, "llm-gpu") &&
    container.node_name == local.llm_gpu_engine_pair_node
  }

  # Runtime ownership for the GPU guest pair is derived from the one engine
  # selector. Container declarations carry engine identity, never a second
  # per-guest engine switch.
  containers_with_engine_runtime = {
    for name, container in var.containers : name => (
      container.llm_gpu_engine_identity != null
      ? merge(container, {
        started       = container.llm_gpu_engine_identity == var.llm_gpu_engine
        start_on_boot = container.llm_gpu_engine_identity == var.llm_gpu_engine
      })
      : contains(keys(local.llm_gpu_engine_legacy_members), name)
      ? merge(container, { started = false, start_on_boot = false })
      : container
    )
  }

  llm_gpu_engine_members = {
    for name, container in local.containers_with_engine_runtime : name => container
    if container.llm_gpu_engine_identity != null
  }
}
