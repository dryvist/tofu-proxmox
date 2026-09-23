# Load-balanced ingress ROUTES, split from locals-ingress-backends.tf so that
# file stays under the shared _file-size 12 KB error threshold. Locals merge
# across files in the module, so this is a pure relocation — the list is
# concatenated into local.ingress_pre exactly as before, the same treatment
# local.iac_platform_routes and local.firecrawl_routes already get.
#
# Routes only. The backend ADDRESS pools these reference live in
# locals-ingress-pools.tf.

locals {
  # Shared by the primary pool and its failover_fallback below, so the two
  # never drift apart.
  openbao_health_check_interval = "30s"
  openbao_health_check_timeout  = "20s"

  ingress_lb_routes = concat(
    # OpenBao HA: one openbao.<domain> route load-balancing the Raft peers.
    # backends (plural) -> multi-server loadBalancer; health_check drops a down
    # node. Omitted if no peer exists.
    #
    # health_check_path is /v1/sys/health WITHOUT ?standbyok — only the active
    # peer returns 200; standbys return 429 and Traefik evicts them, routing
    # every request straight to the active node. Deliberate: writes must hit the
    # Raft leader anyway, and pooling standbys amplifies a real forward-to-leader
    # failure. The `traefik` role renders this path for the route's health check
    # (default "/").
    length(local.openbao_backends) > 0 ? [
      {
        name     = "openbao"
        backends = local.openbao_backends
        port     = local.pipeline_constants.service_ports.openbao_api
        # No sticky: active-only health checks leave exactly one healthy backend,
        # so a cookie adds nothing — and one minted before a fence/election pins
        # the client to an evicted backend.
        sticky            = false
        health_check      = true
        health_check_path = "/v1/sys/health"
        # The pool has one eligible member at any moment, so a single probe
        # that exceeds the estate default empties it. Probe less often and
        # allow a slow answer; the timeout stays below the interval.
        health_check_interval = local.openbao_health_check_interval
        health_check_timeout  = local.openbao_health_check_timeout
        sso                   = false # token/AppRole/JWT API clients (CLI, Terrakube, roles)
        # A nested standby-eligible pool a `failover` service can route to
        # only when the primary pool above has no healthy server — never
        # published as its own route (would leak into ingress/dashboard
        # consumers as a tile with no Host rule).
        failover_fallback = {
          backends              = local.openbao_backends
          health_check_path     = "/v1/sys/health?standbyok=true&perfstandbyok=true"
          health_check_interval = local.openbao_health_check_interval
          health_check_timeout  = local.openbao_health_check_timeout
        }
      }
    ] : [],
    # LiteLLM router pool: llm.<domain> is the OpenAI-compatible API;
    # llm-ui.<domain> is the admin UI on its own hostname, so its browser
    # calls to the API land on the same origin. root_redirect sends the UI
    # host's bare root to its own /ui/ path (rendered as a redirectRegex
    # middleware scoped to that one router in the traefik role).
    # health_check_path reads /health/readiness on both rows: it fails when
    # the database is unreachable, unlike /health/liveliness, and makes no
    # model call. strategy = "hrw" (Rendezvous hashing, Traefik's non-cookie
    # sticky-by-source-IP option) pins a caller to one router without a
    # cookie, which a machine-API client never carries.
    length(local.llm_router_backends) > 0 ? [
      {
        name              = "llm-ui"
        backends          = local.llm_router_backends
        port              = local.pipeline_constants.service_ports.llm_router_api
        root_redirect     = "/ui/"
        strategy          = "hrw"
        health_check      = true
        health_check_path = "/health/readiness"
        sso               = true # browser admin UI — gated
      }
    ] : [],
    # llm.<domain>/ui: the pre-existing admin UI path on the API hostname,
    # kept gated so that path never falls through to the ungated API row
    # below. Same pattern as nautobot/nautobot-api/nautobot-graphql — priority
    # wins the match ahead of the catch-all "llm" row.
    length(local.llm_router_backends) > 0 ? [
      {
        name              = "llm-ui-legacy"
        hostname          = "llm"
        backends          = local.llm_router_backends
        port              = local.pipeline_constants.service_ports.llm_router_api
        path_prefix       = "/ui"
        priority          = 100 # must win the match before the catch-all "llm" row
        health_check      = true
        health_check_path = "/health/readiness"
        sso               = true # browser admin UI — gated
      }
    ] : [],
    # A SEPARATE conditional, not a second element of the one above. The two
    # rows carry different attribute sets (this one takes the default hostname
    # and has no path_prefix/priority), and a tuple holding two differently
    # shaped objects has no common element type to convert to — the conditional
    # then fails to type-check against the empty branch. One row per
    # conditional keeps each pair trivially unifiable, which is why every other
    # block in this file is shaped this way. Adding null placeholders here
    # would type-check but is worse: an explicit null is not an unset optional,
    # so `try()` returns it instead of falling through to the default.
    length(local.llm_router_backends) > 0 ? [
      {
        name              = "llm"
        backends          = local.llm_router_backends
        port              = local.pipeline_constants.service_ports.llm_router_api
        strategy          = "hrw"
        health_check      = true
        health_check_path = "/health/readiness"
        sso               = false # OpenAI-compatible API clients
        # The router bounds every request itself (its per-attempt timeout and
        # fallback ladder); a non-streaming completion sends no byte until the
        # whole answer exists. The ingress therefore applies no first-header
        # limit to this route - "0s" is Traefik's "none" - so its own default
        # cannot cut a request the router is still serving.
        response_header_timeout = "0s"
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
