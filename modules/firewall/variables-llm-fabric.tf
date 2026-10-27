# LLM fabric container-id inputs, one per tag. Split out of variables.tf (which
# reached the shared _file-size 12 KB error threshold) for the same reason
# llm_fabric_rules.tf was split out of locals.tf — the note at the top of that
# file says so explicitly. Variables merge across files within a module.

variable "llm_router_container_ids" {
  description = "Map of LLM router LXC names to IDs (tag-driven: llm-router). LiteLLM proxy fronting the fabric — inbound llm_router_api from internal + outbound internal/HTTPS (llm-fast + off-box model endpoints)."
  type        = map(number)
  default     = {}
}

variable "llm_fast_container_ids" {
  description = "Map of LLM fast-server LXC names to IDs (tag-driven: llm-fast). GPU llama-swap server — inbound llm_fast_api from internal + outbound internal/HTTPS (model/weight fetch)."
  type        = map(number)
  default     = {}
}

variable "llm_gpu_small_router_container_ids" {
  description = "Map of GPU small-router LXC names to IDs (tag-driven: llm-gpu-small-router). GPU serving API — inbound llm_gpu_serving_api from internal."
  type        = map(number)
  default     = {}
}

variable "llm_classify_container_ids" {
  description = "Map of LLM classifier LXC names to IDs (tag-driven: llm-gpu-classify). Laya System One classifier — inbound llm_classify_api from internal."
  type        = map(number)
  default     = {}
}

variable "llm_redis_container_ids" {
  description = "Map of LLM spend-store LXC names to IDs (tag-driven: llm-redis). Shared Redis backing the LiteLLM router pool's cross-instance spend accounting — inbound redis_default from the ai VLAN only, outbound internal only (no WAN)."
  type        = map(number)
  default     = {}
}

variable "gpu_telemetry_container_ids" {
  description = "Map of GPU passthrough LXC names to IDs. NVIDIA DCGM exporter scrape access is attached only to these guests."
  type        = map(number)
  default     = {}
}
