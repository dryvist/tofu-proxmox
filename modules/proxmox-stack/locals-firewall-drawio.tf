locals {
  next_ai_drawio_ingress_src = join(",", local.ingress_hosts)
  next_ai_drawio_mcp_src     = join(",", local.llm_router_backends)
}
