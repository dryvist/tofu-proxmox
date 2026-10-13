# Each commissioned GPU node has one serving container and may also have one
# pinned small-model container. Both carry gpu-passthrough; no other guest gets
# any GPU device or a bind of /dev. Enforced at plan time, natively.
locals {
  gpu_passthrough_tag = "gpu-passthrough"
  gpu_small_role_tag  = "llm-gpu-small"

  gpu_passthrough_containers = {
    for name, container in var.containers : name => container
    if contains(coalesce(try(container.tags, null), []), local.gpu_passthrough_tag)
  }

  llm_gpu_small_role_containers = {
    for name, container in var.containers : name => container
    if contains(coalesce(try(container.tags, null), []), local.gpu_small_role_tag)
  }

  # llm-* serving containers; routers and caches share the prefix but do not serve.
  llm_serving_containers = {
    for name, container in var.containers : name => container
    if startswith(coalesce(try(container.hostname, null), name), "llm-") &&
    !startswith(coalesce(try(container.hostname, null), name), "llm-router-") &&
    !startswith(coalesce(try(container.hostname, null), name), "llm-redis-") &&
    !contains(coalesce(try(container.tags, null), []), local.gpu_small_role_tag)
  }

  gpu_capable_nodes = [
    for node_name, node in var.nodes : node_name
    if contains(coalesce(try(node.tags, null), []), "nvidia-gpu") && coalesce(try(node.commissioned, null), true)
  ]

  gpu_device_access_without_tag = [
    for name, container in var.containers : name
    if !contains(keys(local.gpu_passthrough_containers), name) && anytrue([
      for path in concat(
        [for device in container.device_passthrough : device.path],
        [for mount in container.mount_points : mount.volume],
        ) : (
        path == "/dev" || path == "/dev/" ||
        path == "/dev/dri" || startswith(path, "/dev/dri/") ||
        path == "/dev/kfd" || startswith(path, "/dev/kfd/") ||
        startswith(path, "/dev/nvidia")
      )
    ])
  ]
}

resource "terraform_data" "gpu_passthrough_guard" {
  input = keys(local.gpu_passthrough_containers)

  lifecycle {
    precondition {
      condition = alltrue([
        for node_name in keys(var.nodes) :
        length([
          for container in values(local.gpu_passthrough_containers) : container if container.node_name == node_name
          ]) == (contains(local.gpu_capable_nodes, node_name) ? 1 + length([
            for container in values(local.llm_gpu_small_role_containers) : container if container.node_name == node_name
        ]) : 0)
      ])
      error_message = "Each commissioned nvidia-gpu node must have exactly one serving gpu-passthrough container plus at most one llm-gpu-small container; uncommissioned and non-GPU nodes must have none."
    }

    precondition {
      condition = alltrue([
        for container in values(local.gpu_passthrough_containers) : contains(local.gpu_capable_nodes, container.node_name)
      ])
      error_message = "A gpu-passthrough container must be placed on a commissioned nvidia-gpu node."
    }

    precondition {
      condition     = length(local.gpu_device_access_without_tag) == 0
      error_message = "Device passthrough and bind mounts of /dev/dri, /dev/kfd, /dev/nvidia* or all of /dev require the gpu-passthrough tag; untagged: ${join(", ", local.gpu_device_access_without_tag)}."
    }

    precondition {
      condition = alltrue([
        for container in values(local.gpu_passthrough_containers) :
        can(regex(local.gpu_passthrough_container_name_regex, container.hostname)) &&
        (contains(coalesce(try(container.tags, null), []), local.gpu_small_role_tag) == endswith(container.hostname, "-small"))
      ])
      error_message = "A gpu-passthrough container must have an Ada Lovelace or Blackwell hostname, GDDR 6 or 7 with optional uppercase X, integer VRAM followed by GB, and a role suffix; llm-gpu-small must end in -small."
    }

    precondition {
      condition = alltrue([
        for container in values(local.llm_gpu_small_role_containers) : contains(coalesce(try(container.tags, null), []), local.gpu_passthrough_tag)
      ])
      error_message = "The llm-gpu-small role requires gpu-passthrough."
    }

    precondition {
      condition = alltrue([
        for node_name in toset([for container in values(var.containers) : container.node_name]) :
        length([for container in values(local.llm_gpu_small_role_containers) : container if container.node_name == node_name]) <= 1
      ])
      error_message = "At most one llm-gpu-small container may run on each node."
    }

    precondition {
      condition = alltrue([
        for node_name in toset([for container in values(var.containers) : container.node_name]) :
        length([for container in values(local.llm_serving_containers) : container if container.node_name == node_name]) <= 1
      ])
      error_message = "At most one serving llm-* container may run on each node; llm-router-* and llm-redis-* containers are excluded."
    }
  }
}
