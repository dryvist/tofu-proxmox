# Optional deployment.json object for the CPU LLM pool scaler. The NAME is the
# single identity; install/config/state paths are derived from it in
# constants-llm-cpu-scaler.tf so the string never repeats. Tags name which
# container tags select pool members / the warm instance — also written once
# here and consumed by ansible (load_tofu, llm_router, llm_cpu_scaler) and by
# locals-llm-fabric.tf for the firewall map.
variable "llm_cpu_scaler" {
  description = "CPU LLM pool scaler identity and knobs. Paths are derived from name in constants-llm-cpu-scaler.tf — never restate them here or downstream."
  type = object({
    name              = optional(string, "llm-cpu-scaler")
    poll_interval_sec = optional(number, 60)
    idle_teardown_sec = optional(number, 1200)
    min_free_ram_mb   = optional(number, 40960)
    tags = optional(object({
      moe    = optional(string, "llm-cpu-moe")
      nine_b = optional(string, "llm-cpu-9b")
      warm   = optional(string, "llm-cpu-warm")
      pool   = optional(string, "llm-cpu-pool")
    }), {})
  })
  default = {}
}
