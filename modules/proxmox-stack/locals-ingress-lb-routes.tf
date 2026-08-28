# Load-balanced ingress ROUTES, split from locals-ingress-backends.tf so that
# file stays under the shared _file-size 12 KB error threshold. Locals merge
# across files in the module, so this is a pure relocation — the list is
# concatenated into local.ingress_pre exactly as before, the same treatment
# local.iac_platform_routes and local.firecrawl_routes already get.
#
# Routes only. The backend ADDRESS pools these reference live in
# locals-ingress-pools.tf.

locals {
  ingress_lb_routes = concat(
    # OpenBao HA: one openbao.<domain> route load-balancing the Raft peers.
    # backends (plural) -> multi-server loadBalancer; health_check drops a down
    # node. Omitted if no peer exists.
    #
    # health_check_path is /v1/sys/health WITHOUT ?standbyok — only the active
    # peer returns 200; standbys return 429 and Traefik evicts them, routing
    # every request straight to the active node. Deliberate: writes must hit the
    # Raft leader anyway, and the previous ?standbyok=true pooling meant most
    # requests hit a standby whose forward-to-leader hop is the path that
    # intermittently fails ("internal error"), so pooling standbys amplified the
    # failure (verified 2026-07-20; ansible-proxmox-apps#1125). Trade-off: a brief
    # window during leader election until the health check re-converges — far
    # cheaper than the continuous failure rate standby-pooling caused. The
    # `traefik` role renders this path for the route's health check (default "/").
    length(local.openbao_backends) > 0 ? [
      {
        name     = "openbao"
        backends = local.openbao_backends
        port     = local.pipeline_constants.service_ports.openbao_api
        # No sticky: active-only health checks leave exactly one healthy backend,
        # so a cookie adds nothing — and one minted before a fence/election pins
        # the client to an evicted backend (observed 2026-07-27: persistent 503s
        # while the health check showed a healthy leader).
        sticky            = false
        health_check      = true
        health_check_path = "/v1/sys/health"
        sso               = false # token/AppRole/JWT API clients (CLI, Terrakube, roles)
      }
    ] : [],
    # LiteLLM router pool: llm.<domain> load-balancing the stateless routers.
    # No sticky — every router serves every model from the same config.
    length(local.llm_router_backends) > 0 ? [
      {
        name              = "llm"
        backends          = local.llm_router_backends
        port              = local.pipeline_constants.service_ports.llm_router_api
        health_check      = true
        health_check_path = "/health/liveliness"
        sso               = false # OpenAI-compatible API clients
      }
    ] : [],
    # agentgateway MCP fabric: mcp.<domain> (proxy plane) + agentgateway.<domain>
    # (admin UI) each load-balance every tagged instance. Health = the stats
    # server's /metrics on its own port (health_check_port): the proxy port
    # answers 404/406 to plain GETs, which a same-port health check would read
    # as "down" and eject every healthy server.
    length(local.agentgateway_backends) > 0 ? [
      {
        name              = "mcp"
        backends          = local.agentgateway_backends
        port              = local.pipeline_constants.service_ports.agentgateway_proxy
        health_check      = true
        health_check_path = "/metrics"
        health_check_port = local.pipeline_constants.service_ports.agentgateway_metrics
        sso               = false # MCP tool clients (machines)
      },
      {
        name              = "agentgateway"
        backends          = local.agentgateway_backends
        port              = local.pipeline_constants.service_ports.agentgateway_admin
        health_check      = true
        health_check_path = "/metrics"
        health_check_port = local.pipeline_constants.service_ports.agentgateway_metrics
        sso               = true # browser admin UI — gated
      }
    ] : [],
    local.firecrawl_routes,
    # Hindsight agent memory: one hindsight.<domain> route load-balancing the
    # stateless API replicas. No sticky — every replica serves every bank from
    # the same Postgres. /health is the upstream readiness endpoint.
    length(local.hindsight_backends) > 0 ? [
      {
        name              = "hindsight"
        backends          = local.hindsight_backends
        port              = local.pipeline_constants.memory_ports.hindsight_api
        health_check      = true
        health_check_path = "/health"
        sso               = false # agent/machine memory API
      },
      {
        # Control Plane admin UI (access-key gated in the app). Same attribute
        # shape as the API route above — both arms of the conditional must
        # unify to one object type.
        name              = "hindsight-cp"
        backends          = local.hindsight_backends
        port              = local.pipeline_constants.memory_ports.hindsight_cp
        health_check      = false
        health_check_path = "/"
        sso               = true # browser admin UI — gated
      }
    ] : [],
    # Zammad HA: one zammad.<domain> route load-balancing the application nodes.
    # sticky keeps a browser UI session pinned to one node.
    length(local.zammad_backends) > 0 ? [
      {
        name         = "zammad"
        backends     = local.zammad_backends
        port         = local.pipeline_constants.service_ports.zammad_web
        sticky       = true
        health_check = true
        sso          = true # browser UI — gated
      }
    ] : [],
    # Cribl Stream OTLP trace-span ingest: one otel.<domain> route load-balancing
    # the cribl+stream LXCs' in_otel OTLP/HTTP listener. Backend is plain HTTP
    # (default scheme) — Traefik terminates TLS at websecure and forwards http.
    # No health check: the OTLP listener has no GET-able health path on its own
    # port, and OTLP/HTTP producers retry, so a false-negative eviction would do
    # more harm than a rare span drop to a down node.
    length(local.cribl_stream_backends) > 0 ? [
      {
        name         = "otel"
        backends     = local.cribl_stream_backends
        port         = local.pipeline_constants.service_ports.otel_traces_http
        health_check = false
        sso          = false # OTLP trace-span producers (Claude Code, machines)
      }
    ] : [],
  )
}
