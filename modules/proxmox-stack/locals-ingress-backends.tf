# Ingress backend pools + assembled route list — split from ingress.tf so the
# route TABLE (ingress.tf) stays under the shared _file-size workflow's 12 KB
# error threshold (same locals-split treatment as locals-ingress-ha.tf).
# Locals merge across files in the module.
locals {
  # Ingress HA (keepalived VRRP VIP) locals — ingress_vip / ingress_hosts /
  # ingress_container_keys — live in locals-ingress-ha.tf so this file stays under
  # the shared _file-size workflow's 12 KB error threshold (locals merge across
  # files in the module, same split as locals-honeypot.tf / locals-vm-network.tf).

  # Proxmox cluster UI apex backend pool. Load-balanced across commissioned
  # nodes by role FQDN. Traefik skips backend cert verification.
  proxmox_ui_backends = [
    for name, n in var.nodes : "${n.role}.${var.domain}"
    if n.commissioned
  ]

  # Assembled routes: one {name, ip, port} per fronted service whose backend
  # container is actually defined (others are skipped, so a partial deployment
  # never emits a dangling route). The backend address comes from
  # local.container_address: a static guest's cidrhost IP, or a DNS-first
  # (dhcp = true) guest's FQDN — same hostname-not-IP shape as proxmox_ui_backends.
  # The Splunk VM is appended separately: it is a VM (not in var.containers), so
  # its IP comes from splunk_derived_ip (siem VLAN) rather than container_address.
  ingress_pre = [for route in concat(
    [
      for name, svc in local.ingress_services : {
        name        = name
        hostname    = try(svc.hostname, name)
        path_prefix = try(svc.path_prefix, null)
        priority    = try(svc.priority, null)
        ip          = local.container_address[svc.backend]
        port        = svc.port
        # Serving guest. Published so desc and section derive from it.
        owner = svc.backend
        # Authelia forwardAuth gate flag, consumed by the ansible traefik role.
        # Defaults true (gated) unless the table row opts out (sso = false).
        sso = try(svc.sso, true)
        # Dashboard grouping — see locals-ingress-groups.tf. Inherited from the
        # backend container's VLAN so no second tag list is maintained.
        group = try(svc.group, try(var.containers[svc.backend].vlan, "other"))
      }
      if contains(keys(var.containers), svc.backend)
    ],
    [
      {
        name  = "splunk"
        owner = "splunk"
        ip    = split("/", local.splunk_derived_ip)[0]
        port  = local.pipeline_constants.service_ports.splunk_web
        # Splunk Web serves HTTPS with a self-signed cert, unlike the HTTP
        # container backends. Traefik must speak https to it and skip verify.
        # Consumers default scheme=http / insecure_tls=false when absent.
        scheme       = "https"
        insecure_tls = true
        sso          = true # browser UI — gated
      },
      {
        # Splunk management / REST API (splunkd, 8089) fronted at
        # splunk-mgmt.<domain>. Single label deliberately: the *.<domain>
        # wildcard cert covers splunk-mgmt.<domain> but NOT a nested
        # mgmt.splunk.<domain>. splunkd's mgmt port is HTTPS self-signed, so
        # same https + skip-verify backend as the web route above.
        name         = "splunk-mgmt"
        owner        = "splunk"
        ip           = split("/", local.splunk_derived_ip)[0]
        port         = local.pipeline_constants.service_ports.splunk_mgmt
        scheme       = "https"
        insecure_tls = true
        sso          = false # REST API clients (CLI, automation)
      },
      {
        # Splunk HEC (8088) fronted at splunk-hec.<domain> on the standard
        # TLS entrypoint. HEC senders (the Cribl edges) must use this name:
        # splunk.<domain> resolves to Traefik, which serves nothing on a raw
        # 8088, so a sender dialing <name>:8088 black-holes. Same HTTPS
        # self-signed backend treatment as the other Splunk routes above.
        name         = "splunk-hec"
        owner        = "splunk"
        ip           = split("/", local.splunk_derived_ip)[0]
        port         = local.pipeline_constants.service_ports.splunk_hec
        scheme       = "https"
        insecure_tls = true
        sso          = false # HEC token senders (Cribl edges)
      }
    ],
    # Proxmox cluster UI apex (the ingress subdomain apex), load-balanced.
    # apex=true -> the Traefik Host rule is the base domain itself (no <name>.
    # prefix). backends (plural) -> a multi-server loadBalancer; sticky + health
    # checks give a stable per-browser session + drop a down node from the pool.
    # Omitted entirely if no node is commissioned (empty pool -> no route).
    length(local.proxmox_ui_backends) > 0 ? [
      {
        name         = "proxmox"
        apex         = true
        backends     = local.proxmox_ui_backends
        port         = local.pipeline_constants.service_ports.proxmox_web
        scheme       = "https"
        insecure_tls = true
        sticky       = true
        health_check = true
        sso          = false # tofu provider / API clients share this route
      }
    ] : [],
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
    # IaC automation platform routes (Terrakube + Semaphore on the iac-platform
    # VM) — assembled in locals-ingress-iac.tf to keep this file under the shared
    # _file-size 12 KB gate.
    local.iac_platform_routes
    # hostname defaults to the route name; group for a backend-less route comes
    # from the map in locals-ingress-groups.tf. Route-supplied keys win over both.
    ) : merge({
      hostname = route.name
      group    = try(local.ingress_route_groups[route.name], "other")
      owner    = null
      # ui follows sso: machine clients cannot do a browser login either way.
      # Exceptions in locals-ingress-audience.tf. desc comes from the guest.
      ui = contains(local.ingress_human_unauthed_routes, route.name) ? true : try(route.sso, true)
      # coalesce, not a try chain: an unset optional attribute is null, which
      # try returns rather than falling through. coalesce rejects "" as an
      # argument, so the outer try supplies the empty default.
      desc = try(coalesce(
        try(var.containers[route.owner].summary, null),
        try(local.ingress_pool_descriptions[route.name], null),
      ), "")
  }, route)]

  # Routes per guest — from the assembled list, so pools/VMs count too.
  ingress_owner_route_count = {
    for owner, routes in {
      for r in local.ingress_pre : r.owner => r... if r.owner != null
    } : owner => length(routes)
  }

  # A guest serving 2+ routes is a section. Derived, so nothing declares it.
  ingress = [
    for r in local.ingress_pre : merge(r, {
      section = try(local.ingress_owner_route_count[r.owner], 0) > 1 ? r.owner : null
    })
  ]
}
