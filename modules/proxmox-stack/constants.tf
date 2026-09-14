# Pipeline constants - single source of truth for service, syslog, NetFlow, notification, and vector DB ports
# Referenced by ansible_inventory output for downstream consumption
locals {
  pipeline_constants = {
    # Observability/security data-plane ports — splunk/cribl/grafana/victoria
    # metrics/clickhouse/otel/phoenix/langfuse/smokeping/exporters/elastic —
    # live in constants-observability.tf (12 KB file-size gate, same split as
    # dashboard_ports/ai_log_ports). dashboard_ports: see
    # constants-dashboards.tf.
    service_ports = merge(local.dashboard_ports, local.herdr_ports, local.observability_ports, {
      haproxy_stats = 8404
      apt_cacher_ng = 3142
      # Egress forward-proxy (Squid) for the confined AI agent plane. An
      # `ai-proxied` guest has NO 443-to-any of its own: its only WAN path is
      # CONNECT through this port, where the domain allowlist is enforced.
      # The Proxmox firewall cannot filter on hostname/SNI, so the L3/L4 layer
      # grants reach to the proxy and the proxy decides destinations.
      squid_proxy            = 3128
      object_storage_s3      = 9000
      object_storage_console = 9001
      openbao_api            = 8200
      openbao_cluster        = 8201
      postgres_default       = 5432
      redis_default          = 6379
      ntp                    = 123
      idrac_kvm_r410         = 5410
      idrac_kvm_r710         = 5710
      # Web UIs fronted by Traefik that have no other constant home. Kept here so
      # every port lives in one place and the ingress table (below) references
      # constants, never literals.
      technitium_web    = 5380
      authelia_portal   = 9091
      phpipam_web       = 80
      nautobot_web      = 8080
      vikunja_web       = 3456
      zammad_web        = 8080 # nginx in-guest, own container IP (independent of nautobot's 8080); Traefik-fronted
      homeassistant_web = 8123
      openproject_web   = 80
      # MCP gateway (mcp-gateway tag): single HTTP/SSE endpoint every MCP
      # client (Claude Code, Codex, Cursor, OpenCode) connects to.
      mcp_gateway_web = 4444
      docs_static_web = 80 # nginx document root on the static file host
      homarr_web      = 7575
      # Proxmox cluster web UI (:8006) — fronted by Traefik at the ingress
      # subdomain apex, load-balanced across every commissioned node's UI.
      proxmox_web = 8006
      # Local LLM fabric. llm_fast_api = llama-swap OpenAI-compatible endpoint on
      # the GPU llm-fast guest; llm_router_api = LiteLLM proxy that routes across
      # llm-fast + the larger off-box model endpoints; open_webui_web = the chat
      # UI. ollama_api is retained through the retirement phase (superseded by
      # llama-swap on llm_fast_api).
      llm_fast_api   = 10434
      llm_router_api = 4000
      ollama_api     = 11434
      # llm_cluster_api = the serving host's gated Cluster Mode endpoint (the
      # two-Mac distributed brain); mirrors the loopback cluster port the same
      # way ollama_api mirrors the standalone proxy.
      llm_cluster_api   = 11440
      open_webui_web    = 8080
      docling_serve_api = 5001
      # agentgateway — Rust-written AI-first data plane that unifies MCP
      # (Model Context Protocol), LLM, and A2A (agent-to-agent) traffic into a
      # single proxy. agentgateway_proxy = the MCP/LLM/A2A traffic port callers
      # dial (OpenAI-compatible + native MCP); agentgateway_admin = the admin
      # UI / xDS config-dump port (fronted by Traefik, internal-only);
      # agentgateway_metrics = the stats server's Prometheus /metrics port
      # (upstream serves metrics on a separate statsAddr, not the admin port).
      agentgateway_proxy   = 8080
      agentgateway_admin   = 15000
      agentgateway_metrics = 15020
      # hermes_webhook — the Hermes agent's inbound webhook receiver
      # (`hermes gateway` platform, routes /webhooks/<name>, HMAC-signed).
      # Traefik-fronted as https://hermes.<sub>/webhooks/<name>; gives the one
      # non-A2A agent an event-driven trigger channel on the agent plane.
      hermes_webhook = 8644
      # hermes_dashboard — the authenticated interactive Hermes Dashboard.
      # Traefik fronts it at https://hermes.<subdomain>; the webhook keeps the
      # /webhooks/ path on that same hostname.
      hermes_dashboard = 8080
      # hermes_api — the Hermes agent's inbound job-submission API (`hermes
      # gateway` api_server platform: POST /v1/runs, /api/jobs cron CRUD,
      # bearer-authenticated). Traefik-fronted as https://hermes-api.<sub>;
      # the sanctioned non-exec path to submit work to the agent.
      hermes_api = 8642
      # hermes-donna is a second, independently-identified Hermes agent
      # instance (own container) running the SAME software as hermes-agent,
      # so it resolves the same hermes_webhook/hermes_dashboard/hermes_api
      # keys above — no separate port constants needed.
      # AI orchestration stack web UIs (Traefik-fronted) — n8n, Dify, LangFlow,
      # and Langfuse (LLM trace/cost/eval). ingress.tf references these.
      n8n_web      = 5678
      dify_web     = 80
      langflow_web = 7860
      # LangGraph, self-hosted zero-cloud: `langgraph dev` in-memory server API +
      # its self-hosted Agent Chat UI (Next.js). langgraph_api is deliberately 8124,
      # NOT the LangGraph default 8123, which collides with homeassistant_web above.
      langgraph_api     = 8124
      agent_chat_ui_web = 3000
    })
    syslog_port_map = local.syslog_port_map
    # Legacy flat map: high/backend ports keyed by family, plus the standard
    # default frontend (514, which unifi rides). Derived from syslog_port_map;
    # kept until every downstream consumer reads syslog_port_map directly.
    syslog_ports = merge(
      { default = local.syslog_port_map.unifi.standard },
      { for k, v in local.syslog_port_map : k => v.high }
    )
    netflow_ports = {
      unifi = 2055
    }
    # Ingress HA (keepalived VRRP). keepalived_vrid is the VRRP virtual_router_id
    # the two Traefik instances share to elect a master for the ingress VIP —
    # cluster-unique (no other VRRP group on these VLANs) and referenced by the
    # keepalived role via the inventory, never hardcoded there. VRRP is IP
    # protocol 112 and carries no L4 port, so there is no port constant here.
    ingress_ports = {
      keepalived_vrid = 51
    }
    notification_ports = {
      mailpit_smtp = 1025
      mailpit_web  = 8025
      ntfy_http    = 8080
    }
    vector_db_ports = {
      qdrant_http = 6333
      qdrant_grpc = 6334
    }
    # Agent memory service (Hindsight, ai VLAN). hindsight_api serves the REST
    # API and the built-in MCP endpoint (/mcp); hindsight_cp is the Control
    # Plane admin UI. Two stateless replicas share one Postgres and sit behind
    # a Traefik load-balanced pool (locals-ingress-backends.tf).
    memory_ports = {
      hindsight_api = 8888
      hindsight_cp  = 9999
    }
    # Page-extraction service (Firecrawl, ai VLAN) the Hermes agents call for
    # web_extract. Only the API is exposed; the bundled queue-admin UI is not
    # published, which is what keeps its auth key out of the estate entirely.
    extract_ports = {
      firecrawl_api = 3002
    }
    # AI / LLM log-ingest ports — one dedicated Cribl TCP-JSON receiver per source
    # family (defined in constants-ai-log.tf to keep this file under the shared
    # _file-size 12 KB gate; locals merge across files in the module).
    ai_log_ports = local.ai_log_ports
    # name -> { port, index, sourcetype } routing truth for those receivers
    # (ports derived from ai_log_ports, so the maps cannot drift).
    ai_log_routing = local.ai_log_routing
    # IaC automation platform (Terrakube + Semaphore UI) on the iac-platform VM
    # (docker compose, mgmt VLAN). Host ports published by the compose
    # stack; ingress.tf fronts each behind its own <name>.<domain> route. The
    # Terrakube executor is deliberately NOT listed: it must never be fronted —
    # only the API reaches it, on the compose-internal network.
    iac_platform_ports = {
      terrakube_ui       = 28080
      terrakube_api      = 28081
      terrakube_registry = 28082
      terrakube_dex      = 28083
      semaphore_web      = 28084
    }
    # Honeypot / deception sensor ports (defined in constants-honeypot.tf to
    # keep this file under the shared _file-size 12 KB gate; locals merge
    # across files in the module). See docs/HONEYPOTS.md.
    honeypot_ports = local.honeypot_ports
    # Media stack web UIs. qBittorrent + Prowlarr run inside the download-vpn
    # LXC bound to wg0; their UIs are reachable on the LAN. Sonarr/Radarr/Plex/
    # Seerr/Sortarr are LAN-only guests (per-guest inbound rules in
    # modules/firewall/media_rules.tf). Consumed by ansible-proxmox-apps media
    # roles so no port is hardcoded downstream.
    media_ports = {
      qbittorrent_web = 8080
      prowlarr_web    = 9696
      sonarr_web      = 8989
      radarr_web      = 7878
      plex_web        = 32400
      seerr_web       = 5055
      sortarr_web     = 8787
    }
    serving = local.serving
  }
}
