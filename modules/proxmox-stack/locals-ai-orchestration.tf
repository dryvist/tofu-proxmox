# AI orchestration tier root locals — the AI VLAN CIDR and tag-driven container-id
# maps fed to modules/firewall. Extracted from locals.tf (sibling of ingress.tf)
# to keep that file under the shared _file-size 12 KB error threshold.
locals {
  # AI VLAN CIDR — least-privilege source for the Cribl Edge OTLP ingest path.
  # nonsensitive(): a single VLAN CIDR must flow into the firewall module input;
  # the full network_cidrs map stays sensitive.
  ai_network = nonsensitive(var.network_cidrs["ai"])

  # AI orchestration LXCs (ai-orchestration tag): n8n, Dify, LangFlow, LangGraph, agent-exec.
  # Inbound UI ports from internal + outbound internal/HTTPS (model endpoints,
  # external APIs). agent-exec carries the tag too (egress-only; no UI rule fires).
  ai_orchestration_container_ids = {
    for k, v in var.containers : k => v.vm_id
    if contains(coalesce(try(v.tags, null), []), "ai-orchestration")
  }

  # Langfuse LLM-observability LXC (langfuse tag): web + OTLP ingest on 3000.
  langfuse_container_ids = {
    for k, v in var.containers : k => v.vm_id
    if contains(coalesce(try(v.tags, null), []), "langfuse")
  }

  # AI runner LXCs (ai-github tag): headless coding-agent guests in the
  # `ai-github` egress profile. See modules/firewall/ai_runner_rules.tf — tight
  # egress (internal DNS/NTP/OpenBao + outbound HTTPS only), no blanket internal.
  # Other profiles (ai-terrakube, ai-full-net) are follow-ups: each is a new tag
  # + rules file, this map stays scoped to ai-github.
  ai_github_container_ids = {
    for k, v in var.containers : k => v.vm_id
    if contains(coalesce(try(v.tags, null), []), "ai-github")
  }

  # agentgateway MCP/LLM/A2A data-plane proxy (agentgateway tag). Inbound proxy
  # (8080) from internal AI agents/tools + admin UI (15000) from internal;
  # outbound internal (local LLM fabric) + HTTPS (external MCP servers, LLM APIs).
  agentgateway_container_ids = {
    for k, v in var.containers : k => v.vm_id
    if contains(coalesce(try(v.tags, null), []), "agentgateway")
  }

  # AI runner LXCs (ai-terrakube tag): headless OpenTofu runners for the private
  # Terrakube backend. See modules/firewall/ai_terrakube_rules.tf — internal-only
  # egress (DNS/NTP/OpenBao + Terrakube API/registry + RustFS S3), NO WAN.
  ai_terrakube_container_ids = {
    for k, v in var.containers : k => v.vm_id
    if contains(coalesce(try(v.tags, null), []), "ai-terrakube")
  }

  # AI runner LXCs (ai-full-net tag): coding-agent guests needing general web
  # access. See modules/firewall/ai_full_net_rules.tf — internal DNS/NTP/OpenBao
  # + outbound HTTPS (443) to any; no blanket internal reach.
  ai_full_net_container_ids = {
    for k, v in var.containers : k => v.vm_id
    if contains(coalesce(try(v.tags, null), []), "ai-full-net")
  }
}
