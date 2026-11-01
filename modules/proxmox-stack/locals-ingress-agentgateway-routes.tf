# The two public aliases share this one metrics health contract and the same
# canonical primary/fallback addresses; their traffic ports and auth stay distinct.
locals {
  agentgateway_health_check = {
    path = "/metrics"
    port = local.pipeline_constants.service_ports.agentgateway_metrics
  }

  agentgateway_ingress_routes = local.agentgateway_ingress_enabled ? [
    {
      name              = "mcp"
      backends          = local.agentgateway_backends
      port              = local.pipeline_constants.service_ports.agentgateway_proxy
      health_check      = true
      health_check_path = local.agentgateway_health_check.path
      health_check_port = local.agentgateway_health_check.port
      sso               = false # MCP tool clients (machines)
      # Native failover stays health-driven; no request-status trigger or replay.
      failover_fallback = {
        backends          = local.agentgateway_fallback_backends
        health_check_path = local.agentgateway_health_check.path
      }
    },
    {
      name              = "agentgateway"
      backends          = local.agentgateway_backends
      port              = local.pipeline_constants.service_ports.agentgateway_admin
      health_check      = true
      health_check_path = local.agentgateway_health_check.path
      health_check_port = local.agentgateway_health_check.port
      sso               = true # browser admin UI — gated
      # The same native health signal and membership order as the MCP alias.
      failover_fallback = {
        backends          = local.agentgateway_fallback_backends
        health_check_path = local.agentgateway_health_check.path
      }
    }
  ] : []
}

# shortcut: /metrics proves stats-listener liveness, not proxy or sidecar readiness.
