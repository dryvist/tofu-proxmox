# LLM router health-check paths published for downstream consumers.
locals {
  llm_router_probe_paths = {
    liveliness = "/health/liveliness"
    readiness  = "/health/readiness"
  }
}
