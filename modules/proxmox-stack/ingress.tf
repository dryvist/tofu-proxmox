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
  ingress_services = {
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
    # llm is fronted as a load-balanced router pool (llm_router_backends below).
    chat   = { backend = "open-webui", port = local.pipeline_constants.service_ports.open_webui_web }
    qdrant = { backend = "qdrant", port = local.pipeline_constants.vector_db_ports.qdrant_http, sso = false } # vector API for agents/MCP
    # AI orchestration stack UIs (ai VLAN) + Langfuse LLM observability (siem VLAN).
    n8n      = { backend = "n8n", port = local.pipeline_constants.service_ports.n8n_web }
    dify     = { backend = "dify", port = local.pipeline_constants.service_ports.dify_web }
    langflow = { backend = "langflow", port = local.pipeline_constants.service_ports.langflow_web }
    langfuse = { backend = "langfuse", port = local.pipeline_constants.service_ports.langfuse_web }
    # agentgateway + mcp are fronted as load-balanced pools (agentgateway_backends
    # in locals-ingress-backends.tf), same as llm/openbao — not single rows here.
    # LangGraph (self-hosted): the `langgraph dev` server API + its Agent Chat UI,
    # both backed by the one `langgraph` guest. Chat UI is the primary play surface;
    # the API host also lets browser Studio point its ?baseUrl at it.
    langgraph        = { backend = "langgraph", port = local.pipeline_constants.service_ports.langgraph_api, sso = false } # API + Studio ?baseUrl clients
    "langgraph-chat" = { backend = "langgraph", port = local.pipeline_constants.service_ports.agent_chat_ui_web }
    # Hermes Dashboard is the primary interactive UI. Its route owns the host
    # root; the webhook below retains its established path on the same host.
    "hermes-dashboard" = { hostname = "hermes", backend = "hermes-agent", port = local.pipeline_constants.service_ports.hermes_dashboard }
    # Hermes agent inbound webhook front door: https://hermes.<domain>/webhooks/<name>
    # -> hermes-agent container : hermes_webhook (HMAC-signed, event-driven trigger
    # for the one non-A2A agent). Guest firewall opens the port from internal.
    hermes = { hostname = "hermes", path_prefix = "/webhooks/", priority = 100, backend = "hermes-agent", port = local.pipeline_constants.service_ports.hermes_webhook, sso = false } # HMAC-signed webhooks
    # Hermes agent inbound job-submission API: https://hermes-api.<domain>/v1/runs
    # -> hermes-agent container : hermes_api (`hermes gateway` api_server platform,
    # bearer-authenticated). The sanctioned non-exec job path; internal-only firewall.
    "hermes-api"    = { backend = "hermes-agent", port = local.pipeline_constants.service_ports.hermes_api, sso = false } # bearer-authenticated job API
    smokeping       = { backend = "smokeping", port = local.pipeline_constants.service_ports.smokeping_web }
    "haproxy-stats" = { backend = "haproxy", port = local.pipeline_constants.service_ports.haproxy_stats }
  }
}
