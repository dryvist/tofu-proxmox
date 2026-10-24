# llm-fast — the GPU inference endpoints. Inbound from internal networks.
# Kept apart from llm_fabric_rules.tf to stay under the shared file-size gate;
# local.svc_ports / local.internal_src come from locals files in this module.
locals {
  llm_fast_services_rules = [
    { proto = "tcp", dport = tostring(local.svc_ports.llm_fast_api), source = local.internal_src, comment = "LLM fast / llama-swap server (TCP ${local.svc_ports.llm_fast_api}) from internal" },
    # The co-resident small engine listens on the next port (see the serving role's co-resident API port).
    { proto = "tcp", dport = tostring(local.svc_ports.llm_fast_api + 1), source = local.internal_src, comment = "LLM fast co-resident small engine (TCP ${local.svc_ports.llm_fast_api + 1}) from internal" },
    { proto = "tcp", dport = tostring(local.svc_ports.llm_fast_trial_api), source = local.internal_src, comment = "LLM small trial engine (TCP ${local.svc_ports.llm_fast_trial_api}) from internal" },
  ]
}
