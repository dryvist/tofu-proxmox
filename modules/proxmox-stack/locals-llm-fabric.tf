# Local LLM fabric root locals — tag-driven container-id maps fed to
# modules/firewall. Sibling of locals-ai-orchestration.tf; kept out of locals.tf
# so that file stays under the shared _file-size 12 KB error threshold.
locals {
  # llm-fast LXCs (llm-fast tag): the GPU fast/small-model server (llama-swap,
  # OpenAI-compatible on llm_fast_api). Inbound llm_fast_api from internal.
  llm_fast_container_ids = {
    for k, v in var.containers : k => v.vm_id
    if length(setintersection(
      try(v.tags, []),
      concat(["llm-fast"], local.llm_cpu_scaler.pool_tags)
    )) > 0
  }

  # llm-router LXCs (llm-router tag): the LiteLLM proxy fronting the fabric
  # (llm_router_api). Inbound llm_router_api from internal.
  llm_router_container_ids = {
    for k, v in var.containers : k => v.vm_id
    if contains(try(v.tags, []), "llm-router")
  }

  # llm-redis LXCs (llm-redis tag): the shared store the router pool counts
  # spend in. Its own guest rather than colocated with a router, because the
  # pool has multiple members and a store inside one of them would give each
  # member a private counter — the miscount that made an earlier spend ceiling
  # dishonest. See roles/redis in ansible-proxmox-ai.
  llm_redis_container_ids = {
    for k, v in var.containers : k => v.vm_id
    if contains(try(v.tags, []), "llm-redis")
  }

  # Every container's mount_points with read_only resolved once. Fed to
  # modules/proxmox-container (main.tf) to create the mounts and to
  # inventory_containers.tf to publish the shared models mount's spec, so the
  # two can never derive read_only differently.
  container_mount_points = {
    for k, v in var.containers : k => [
      for mp in v.mount_points : merge(mp, {
        read_only = mp.read_only != null ? mp.read_only : (
          contains(keys(local.llm_fast_container_ids), k) && mp.path == var.llm_models_mount_path
        )
      })
    ]
  }
}
