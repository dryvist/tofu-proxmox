# Firewall module call — extracted from main.tf into its own file so main.tf
# stays under the shared _file-size workflow's 12 KB gate. This block grows
# with every new service (each adds a *_container_ids pass), so it lives here
# rather than crowding main.tf (same split rationale as the locals-*.tf files).

# Firewall module - rules for Splunk and containers
module "firewall" {
  source = "../firewall"

  node_name = var.proxmox_node

  splunk_vm_ids = merge(
    {
      for k, v in var.vms : k => v.vm_id
      if contains(try(v.tags, []), "splunk")
    },
    {
      "splunk-vm" = module.splunk_vm.vm_id
    }
  )

  splunk_container_ids = {
    for k, v in var.containers : k => v.vm_id
    if contains(try(v.tags, []), "splunk")
  }

  # Pipeline containers: HAProxy (haproxy tag) and Cribl Edge (cribl + edge tags)
  # These receive syslog and NetFlow data from network devices
  pipeline_container_ids = local.pipeline_container_ids

  # Notification containers: Mailpit and ntfy (notifications tag)
  notification_container_ids = local.notification_container_ids

  # Vector database containers: Qdrant (vectordb tag)
  vectordb_container_ids = local.vectordb_container_ids

  # Hindsight agent-memory containers (hindsight tag) — API 8888 / CP UI 9999
  hindsight_container_ids = local.hindsight_container_ids

  # RAG engine containers: LlamaIndex (rag tag)
  rag_container_ids = local.rag_container_ids

  # APT caching proxy containers: apt-cacher-ng (apt-cache tag)
  apt_cacher_ng_container_ids = local.apt_cacher_ng_container_ids

  # Cribl Stream containers: cribl + stream tags (receives from Edge, routes to Splunk)
  cribl_stream_container_ids = local.cribl_stream_container_ids

  # Cribl Edge containers: cribl + edge tags — subset of pipeline_container_ids
  # that gets license-telemetry HTTPS egress
  cribl_edge_container_ids = local.cribl_edge_container_ids

  # Object storage (object-storage tag) — RustFS.
  s3_container_ids = local.s3_container_ids

  # OpenBao secrets-management containers (openbao tag)
  openbao_container_ids = local.openbao_container_ids

  # Postgres + Nautobot + Vikunja containers — 5432 / 8080 / 3456 from internal
  postgres_container_ids = local.postgres_container_ids
  nautobot_container_ids = local.nautobot_container_ids
  vikunja_container_ids  = local.vikunja_container_ids
  authelia_container_ids = local.authelia_container_ids
  zammad_container_ids   = local.zammad_container_ids

  # Ingress (Traefik HA) containers (ingress tag) — define-disabled guest firewall
  # that pre-allows keepalived VRRP + 80/443 so a later enforcement flip is safe.
  ingress_container_ids = local.ingress_container_ids

  # iDRAC KVM LXC: tagged "idrac" (domistyle/idrac6-based viewers, Docker-in-LXC)
  idrac_kvm_container_ids = local.idrac_kvm_container_ids

  # Network-quality monitoring LXC: tagged "monitoring" (SmokePing + speedtest-exporter)
  monitoring_container_ids = local.monitoring_container_ids

  # LAN-only media LXCs: media tag minus the VPN-locked downloader (its in-guest
  # killswitch is the boundary; see locals-media.tf)
  media_container_ids = local.media_container_ids

  # Hermes Agent LXC: tagged "hermes-agent" (autonomous agent, broad HTTPS egress)
  hermes_agent_container_ids = local.hermes_agent_container_ids

  # AI orchestration LXCs: tagged "ai-orchestration" (n8n, Dify, LangFlow, LangGraph, agent-exec)
  ai_orchestration_container_ids = local.ai_orchestration_container_ids

  # Langfuse LLM-observability LXC: tagged "langfuse"
  langfuse_container_ids = local.langfuse_container_ids

  # LLM fabric LXCs: llm-router (LiteLLM proxy) + llm-fast (GPU llama-swap server)
  llm_router_container_ids = local.llm_router_container_ids
  llm_fast_container_ids   = local.llm_fast_container_ids

  # agentgateway MCP/LLM/A2A data-plane proxy (agentgateway tag).
  agentgateway_container_ids = local.agentgateway_container_ids

  # AI runner LXCs (ai-github tag) — headless coding agents, tight egress profile.
  ai_github_container_ids = local.ai_github_container_ids

  # AI runner LXCs (ai-terrakube tag) — headless OpenTofu runners, internal-only
  # egress (no WAN). ai-full-net tag — coding agents with general 443-to-any.
  ai_terrakube_container_ids = local.ai_terrakube_container_ids
  ai_full_net_container_ids  = local.ai_full_net_container_ids

  # Honeypots (honeypot/notify/tpot tags); filters in locals-honeypot.tf.
  honeypot_container_ids        = local.honeypot_container_ids
  honeypot_notify_container_ids = local.honeypot_notify_container_ids
  tpot_vm_ids                   = local.tpot_vm_ids


  # Pipeline constants: single source of truth for service ports (DRY)
  pipeline_constants = local.pipeline_constants

  management_network = local.management_network
  splunk_network     = join(",", local.splunk_network_ips)
  # Derived from the private RustFS VLAN CIDR map (locals.tf) — no committed ranges.
  internal_networks = local.internal_networks
  # AI VLAN CIDR — least-privilege source scope for the Cribl Edge OTLP ingest.
  ai_network = local.ai_network
  # Per-VLAN CIDR map for zero-trust rule source scoping (staged disabled).
  network_cidrs = nonsensitive(var.network_cidrs)

  depends_on = [module.vms, module.containers, module.splunk_vm]
}
