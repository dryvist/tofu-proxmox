# Next AI Draw.io's browser UI is tag-selected from the shared Docker AI guests.
# Only the web listener is routed; its MCP listener remains private.
locals {
  next_ai_drawio_ingress_routes = length(local.next_ai_drawio_backends) > 0 ? [
    {
      name     = "drawio"
      backends = local.next_ai_drawio_backends
      port     = local.pipeline_constants.service_ports.next_ai_drawio_web
      sso      = true
    }
  ] : []
}
