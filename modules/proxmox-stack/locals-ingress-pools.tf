# Ingress HA backend POOLS — split from locals-ingress-backends.tf so both
# files stay under the shared _file-size workflow's 12 KB error threshold
# (locals merge across files in the module, same split as locals-ingress-ha.tf).
locals {
  # Generic tag-keyed HA backend pools (DRY: one derivation for every pooled
  # service instead of a copy-pasted keys/addresses local pair per app). Every
  # LXC carrying the tag joins that tag's pool; the sort keeps route rendering
  # deterministic; skip-missing-peers falls out naturally (an undeclared or
  # gated-off instance simply isn't in var.containers). Adding the next pooled
  # app = add its tag here + one route entry below — nothing else.
  pooled_backend_tags = ["openbao", "hindsight", "zammad", "agentgateway"]
  tag_backend_pools = {
    for tag in local.pooled_backend_tags : tag => [
      for k in sort([
        for k, v in var.containers : k
        if contains(coalesce(try(v.tags, null), []), tag)
      ]) : local.container_address[k]
    ]
  }

  # OpenBao Raft HA pool: standby peers forward to the active node; the
  # health-check path below deliberately evicts standbys (see route comment).
  openbao_backends = local.tag_backend_pools["openbao"]

  # LiteLLM router pool: THE fabric endpoint (https://llm.<domain>/v1) for every
  # consumer, load-balanced across the stateless router guests. Name-keyed (not
  # tag-keyed) because the routers predate the tag convention.
  llm_router_backends = [
    for k in ["llm-router-1", "llm-router-2", "llm-router-3"] : local.container_address[k]
    if contains(keys(var.containers), k)
  ]

  # Hindsight agent-memory pool: stateless replicas (all state in the ai-VLAN
  # Postgres cluster), no sticky. Clients — agentgateway's MCP target, Hermes
  # remote memory, Claude Code — all dial the one pooled hostname.
  hindsight_backends = local.tag_backend_pools["hindsight"]

  # Zammad HA pool (sticky sessions at the route).
  zammad_backends = local.tag_backend_pools["zammad"]

  # agentgateway MCP-fabric pool: the only path agents (Hermes) have to the
  # splunk/context7/qdrant/memory MCP targets, so it is the one pool whose loss
  # blacks out the whole tool plane (2026-07-24 pve1 incident). Instances are
  # stateless (identical config from the agentgateway_docker role; targets are
  # themselves pooled or external), so no sticky.
  agentgateway_backends = local.tag_backend_pools["agentgateway"]

  # Cribl Stream OTLP pool: LXCs tagged cribl + stream, fronting the in_otel
  # OTLP/HTTP trace-span listener at otel.<domain>. Two-tag identity (matches
  # cribl_stream_container_ids in locals.tf), so it stays a custom derivation
  # rather than the single-tag generic pool. Stateless per request — no sticky.
  cribl_stream_backends = [
    for k in sort([
      for k, v in var.containers : k
      if contains(coalesce(try(v.tags, null), []), "cribl") && contains(coalesce(try(v.tags, null), []), "stream")
    ]) : local.container_address[k]
  ]
}
