# The single path the llama_cpp Ansible role asserts is mounted read-only
# (roles/llama_cpp/tasks/main.yml in dryvist/ansible-proxmox-ai). Declared once
# here so main.tf's mount_points derivation, the published inventory
# (local.inventory_containers), and any future consumer share the same string
# instead of each hard-coding it.
#
# Default is the path deployment.json ACTUALLY mounts today on llm-fast and
# llm-light ("/var/lib/llm" — confirmed via `tofu state show` against the live
# workspace) rather than the sibling path the ansible role's own default
# assumed ("/var/lib/llama-cpp/models", never mounted by any guest). The
# ansible_inventory now publishes this path per container
# (containers[*].models_mount_path), so the role can derive its
# llama_cpp_models_dir from tofu instead of carrying a second, disagreeing
# default.
variable "llm_models_mount_path" {
  description = "Path of the shared model-weights mount that every llm fabric LXC (local.llm_fast_container_ids) must have read-only."
  type        = string
  default     = "/var/lib/llm"
}
