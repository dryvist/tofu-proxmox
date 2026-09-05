# Traefik HTTPS ingress route table — the SINGLE source for every service the
# reverse proxy fronts. The ansible-proxmox-apps `traefik` and `technitium_dns`
# roles consume `ansible_inventory.ingress` instead of each hand-listing hosts
# (the previous DRY violation). Add/remove a fronted service in ONE place here.
#
# Extracted from locals.tf into its own file so locals.tf stays under the shared
# _file-size workflow's 12 KB limit; both files declare locals in the same module.
locals {
  # name = stable router/service identifier. hostname defaults to name, but a
  # service may share a hostname with another path-specific route.
  # backend = the container key whose IP is resolved from the inventory.
  # port = a pipeline_constants reference (never a literal, so ports stay DRY).
  # sso = whether Traefik attaches the Authelia forwardAuth middleware to the
  #       route (default true when omitted). false for machine/API endpoints
  #       (clients cannot do a browser login) and for apps whose non-browser
  #       clients authenticate natively (e.g. Plex apps).
  ingress_services = merge(local.hermes_agent_routes, {
    # Authelia portal itself — never gated (it IS the login page).
    authelia    = { backend = "authelia", port = local.pipeline_constants.service_ports.authelia_portal, sso = false }
    plex        = { backend = "plex", port = local.pipeline_constants.media_ports.plex_web, sso = false } # Plex clients auth via plex.tv
    seerr       = { backend = "seerr", port = local.pipeline_constants.media_ports.seerr_web }
    sonarr      = { backend = "sonarr", port = local.pipeline_constants.media_ports.sonarr_web }
    radarr      = { backend = "radarr", port = local.pipeline_constants.media_ports.radarr_web }
    sortarr     = { backend = "sortarr", port = local.pipeline_constants.media_ports.sortarr_web }
    qbittorrent = { backend = "download-vpn", port = local.pipeline_constants.media_ports.qbittorrent_web }
    prowlarr    = { backend = "download-vpn", port = local.pipeline_constants.media_ports.prowlarr_web }
    technitium  = { backend = "technitium-dns", port = local.pipeline_constants.service_ports.technitium_web }
    phpipam     = { backend = "phpipam", port = local.pipeline_constants.service_ports.phpipam_web }
    # Nautobot's browser UI is SSO-gated. Its native API and GraphQL inventory
    # clients retain their token-authenticated paths on the same hostname.
    nautobot           = { backend = "nautobot", port = local.pipeline_constants.service_ports.nautobot_web }
    "nautobot-api"     = { hostname = "nautobot", path_prefix = "/api/", priority = 100, backend = "nautobot", port = local.pipeline_constants.service_ports.nautobot_web, sso = false }
    "nautobot-graphql" = { hostname = "nautobot", path_prefix = "/graphql/", priority = 100, backend = "nautobot", port = local.pipeline_constants.service_ports.nautobot_web, sso = false }
    vikunja            = { backend = "vikunja", port = local.pipeline_constants.service_ports.vikunja_web, sso = false } # MCP API tokens hit /api/v1 on this host
    "object-storage"   = { backend = "s3", port = local.pipeline_constants.service_ports.object_storage_console }
    # RustFS S3 API fronted by a valid-TLS hostname. Path-style S3 format.
    s3 = { backend = "s3", port = local.pipeline_constants.service_ports.object_storage_s3, sso = false } # machine S3 clients
    # openbao is fronted as a load-balanced pool (openbao_backends below).
    mailpit           = { backend = "mailpit", port = local.pipeline_constants.notification_ports.mailpit_web }
    ntfy              = { backend = "ntfy", port = local.pipeline_constants.notification_ports.ntfy_http, sso = false }             # publish clients POST here
    "honeypot-notify" = { backend = "honeypot-notify", port = local.pipeline_constants.honeypot_ports.apprise_api, sso = false }    # machine notify API
    homeassistant     = { backend = "homeassistant", port = local.pipeline_constants.service_ports.homeassistant_web, sso = false } # companion apps auth natively
    openproject       = { backend = "openproject", port = local.pipeline_constants.service_ports.openproject_web }
    prometheus        = { backend = "prometheus", port = local.pipeline_constants.service_ports.prometheus_web }
    homarr            = { backend = "homarr", port = local.pipeline_constants.service_ports.homarr_web }
    # llm is fronted as a load-balanced router pool (llm_router_backends below).
    chat   = { backend = "open-webui", port = local.pipeline_constants.service_ports.open_webui_web }
    qdrant = { backend = "qdrant", port = local.pipeline_constants.vector_db_ports.qdrant_http, sso = false } # vector API for agents/MCP
    # AI orchestration stack UIs (ai VLAN) + Langfuse/Phoenix LLM observability (siem VLAN).
    n8n      = { backend = "n8n", port = local.pipeline_constants.service_ports.n8n_web }
    dify     = { backend = "dify", port = local.pipeline_constants.service_ports.dify_web }
    langflow = { backend = "langflow", port = local.pipeline_constants.service_ports.langflow_web }
    langfuse = { backend = "langfuse", port = local.pipeline_constants.service_ports.langfuse_web }
    # phoenix's OTLP/HTTP ingest path (/v1/traces) is exempted from the Authelia
    # forwardAuth middleware on the Ansible side (a resource regex in
    # ansible-proxmox-apps), the same way Langfuse's ingest path is — this row
    # stays a single sso-gated route, never a second sso = false row, or the
    # whole UI would be exposed unauthenticated.
    phoenix = { backend = "phoenix", port = local.pipeline_constants.service_ports.phoenix_web }
    # docling-serve — Open WebUI's content-extraction (OCR/layout) backend. The
    # only caller is Open WebUI's server-side loader posting to /v1/convert/file,
    # so sso = false: an SSO redirect would break a machine-to-machine POST.
    "docling-serve" = { backend = "docling-serve", port = local.pipeline_constants.service_ports.docling_serve_api, sso = false }
    # agentgateway + mcp are fronted as load-balanced pools (agentgateway_backends
    # in locals-ingress-backends.tf), same as llm/openbao — not single rows here.
    # LangGraph (self-hosted): the `langgraph dev` server API + its Agent Chat UI,
    # both backed by the one `langgraph` guest. Chat UI is the primary play surface;
    # the API host also lets browser Studio point its ?baseUrl at it.
    langgraph        = { backend = "langgraph", port = local.pipeline_constants.service_ports.langgraph_api, sso = false } # API + Studio ?baseUrl clients
    "langgraph-chat" = { backend = "langgraph", port = local.pipeline_constants.service_ports.agent_chat_ui_web }
    # Every Hermes AGENT's routes (dashboard, webhook, job API, and the two
    # co-located third-party UIs) are generated per agent from the hermes-agent
    # tag in locals-hermes-routes.tf and merged in below — adding an agent to
    # the desired state publishes its whole route set with no edit here.
    #
    # hermes-ui companion guest runs two DIFFERENT apps behind two distinct
    # host ports (both default to 3000 upstream): hermes-workspace (the
    # Hermes web workspace, primary UI) and mission-control (an unrelated
    # product co-located in this container, gateway target is OpenClaw).
    # herdr — the agent multiplexer. Only the UI half is fronted: herdr-remote's
    # relay serves the web/phone dashboard and the approve-a-blocked-agent
    # buttons. Its own token auth stays on underneath, but the Authelia gate
    # (sso omitted => true) is what makes it safe to expose at all, and it is
    # why the upstream's optional Cloudflare tunnel is deliberately NOT used.
    #
    # The `herdr` server guest has no route: it is reached over SSH
    # (`herdr --remote herdr`). Its Slack bridge needs none either — Slack
    # Socket Mode is an outbound WebSocket, so nothing has to reach in.
    herdr = { backend = "herdr-ui", port = local.pipeline_constants.service_ports.herdr_relay_ws }

    "hermes-ui"       = { backend = "hermes-ui", port = local.pipeline_constants.service_ports.hermes_ui_workspace }
    "mission-control" = { backend = "hermes-ui", port = local.pipeline_constants.service_ports.hermes_ui_mission_control }
    # Estate dashboards. All three are populated from local.ingress itself, so
    # every fronted service appears on every board without a second list.
    # Browser-only surfaces: each takes the default gate (sso omitted => true).
    # Glance in particular ships NO authentication of its own, so the Authelia
    # forwardAuth here is the only thing in front of it.
    homepage = { backend = "homepage", port = local.pipeline_constants.service_ports.homepage_web }
    glance   = { backend = "glance", port = local.pipeline_constants.service_ports.glance_web }
    # Catalog synthetics (Gatus) + keystone status page (Uptime Kuma) on the
    # shared `status` guest. Browser-only, default Authelia gate.
    gatus         = { backend = "status", port = local.pipeline_constants.service_ports.gatus_web }
    "uptime-kuma" = { backend = "status", port = local.pipeline_constants.service_ports.uptime_kuma_web }
    # Grafana metrics UI (observability guest). Browser-only, default gate.
    grafana         = { backend = "grafana", port = local.pipeline_constants.service_ports.grafana_web }
    smokeping       = { backend = "smokeping", port = local.pipeline_constants.service_ports.smokeping_web }
    "haproxy-stats" = { backend = "haproxy", port = local.pipeline_constants.service_ports.haproxy_stats }
    # Static file host. Browser-only, so it takes the default gate (sso omitted
    # -> true) rather than opting out the way the machine/API rows above do.
    "docs-static" = { backend = "docs-static", port = local.pipeline_constants.service_ports.docs_static_web }

    # Additional user-facing app services (clean portless HTTPS routes)
    healthchecks = { backend = "healthchecks", port = local.pipeline_constants.service_ports.healthchecks_web }
    immich       = { backend = "immich", port = local.pipeline_constants.service_ports.immich_web }
    zot          = { backend = "registry", port = local.pipeline_constants.service_ports.zot_web }
    autobrr      = { backend = "download-vpn", port = local.pipeline_constants.service_ports.autobrr_web }
    "idrac-kvm"  = { backend = "idrac-kvm", port = local.pipeline_constants.service_ports.idrac_kvm_web }
  })
}
