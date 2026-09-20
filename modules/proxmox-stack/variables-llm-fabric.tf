# The single path the llama_cpp Ansible role asserts is mounted read-only
# (roles/llama_cpp/tasks/main.yml in dryvist/ansible-proxmox-ai). Declared once
# here so main.tf's mount_points derivation and any future consumer share the
# same string instead of each hard-coding it.
variable "llm_models_mount_path" {
  description = "Path of the shared model-weights mount that every llm fabric LXC (local.llm_fast_container_ids) must have read-only."
  type        = string
  default     = "/var/lib/llama-cpp/models"
}
