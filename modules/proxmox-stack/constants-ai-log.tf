# AI / LLM log-ingest ports — one dedicated Cribl TCP-JSON receiver per source
# family, HAProxy-fronted (LB to the Cribl Stream pair, mirroring the claude S2S
# path). Cribl best practice is a dedicated port per source so routing is by
# listener, not payload inspection. The backend flow reuses the existing
# cribl_s2s (10300) receiver on Stream; these frontends are opened on the
# pipeline (HAProxy) containers by the ai-log-ingest security group.
#
# Split into its own file (referenced from constants.tf as local.ai_log_ports)
# so constants.tf stays under the shared _file-size 12 KB error threshold;
# locals merge across files in the module. The Splunk index each lands in is
# noted inline; the indexes themselves are created in ansible-splunk.
locals {
  ai_log_ports = {
    claude_code    = 10311 # MacBook claude-code IO logs      -> index=claude
    codex_cli      = 10312 # MacBook codex CLI logs           -> index=codex (new)
    agy_cli        = 10313 # MacBook agy/antigravity CLI logs -> index=gemini
    copilot_cli    = 10314 # MacBook GitHub Copilot logs      -> index=openai
    vscode         = 10315 # VS Code telemetry                -> index=vscode
    macstudio_llm  = 10321 # Mac Studio llama-swap + vllm-mlx -> index=llm
    macstudio_gate = 10322 # Mac Studio caddy LLM-gate access -> index=llm
    homelab_llm    = 10323 # homelab llama_cpp + llm_router   -> index=llm
    openbao_audit  = 10331 # OpenBao file audit device        -> index=openbao_audit
    hermes_agent   = 10332 # Hermes agent gateway + watchdog syslog -> index=hermes (new)

    # Docker-in-LXC AI services (journald log-driver -> rsyslog program route
    # -> this dedicated port), one index per service/vendor rather than a
    # shared catch-all — see ai_log_index_map below.
    agentgateway_docker  = 10341 # agentgateway + MCP sidecars stack -> index=agentgateway (new)
    dify_docker          = 10342 # Dify LLMOps stack                 -> index=dify (new)
    hindsight_docker     = 10343 # Hindsight memory service (HA pair) -> index=hindsight (new)
    langflow_docker      = 10344 # LangFlow app + postgres           -> index=langflow (new)
    langfuse_docker      = 10345 # Langfuse observability stack      -> index=langfuse (new)
    langgraph_docker     = 10346 # LangGraph API + chat UI           -> index=langgraph (new)
    qdrant_docker        = 10347 # Qdrant vector database            -> index=qdrant (new)
    docling_serve_docker = 10348 # docling-serve OCR/extraction      -> index=docling (new)
    semaphore_docker     = 10349 # Semaphore Ansible run UI          -> index=semaphore (new)
    clickhouse_docker    = 10350 # ClickHouse OLAP store             -> index=clickhouse (new)
    phoenix_docker       = 10351 # Arize Phoenix LLM observability   -> index=phoenix (new)
  }

  # Splunk landing zone per source, keyed to the SAME names as ai_log_ports so
  # the two maps cannot drift apart (ai_log_routing derives its port from
  # ai_log_ports; a name mismatch is a plan-time error). This is the single
  # routing truth the downstream repos consume via ansible_inventory.constants:
  # HAProxy renders one frontend per entry, Cribl Stream one tcpjson/syslog
  # input per entry, and the ai_stamp pipeline stamps index/sourcetype from it.
  # ai_log_ports itself stays map(number) — the firewall module types it, and
  # it is already applied — so the routing metadata lives in this additive map.
  ai_log_index_map = {
    claude_code    = { index = "claude", sourcetype = "claude:code" }
    codex_cli      = { index = "codex", sourcetype = "codex:cli" }
    agy_cli        = { index = "gemini", sourcetype = "antigravity:cli" }
    copilot_cli    = { index = "openai", sourcetype = "copilot:cli" }
    vscode         = { index = "vscode", sourcetype = "vscode:telemetry" }
    macstudio_llm  = { index = "llm", sourcetype = "llamaswap" }
    macstudio_gate = { index = "llm", sourcetype = "caddy:access" }
    homelab_llm    = { index = "llm", sourcetype = "llamaswap" }
    openbao_audit  = { index = "openbao_audit", sourcetype = "openbao:audit" }
    hermes_agent   = { index = "hermes", sourcetype = "hermes:agent" }

    agentgateway_docker  = { index = "agentgateway", sourcetype = "agentgateway:app" }
    dify_docker          = { index = "dify", sourcetype = "dify:app" }
    hindsight_docker     = { index = "hindsight", sourcetype = "hindsight:app" }
    langflow_docker      = { index = "langflow", sourcetype = "langflow:app" }
    langfuse_docker      = { index = "langfuse", sourcetype = "langfuse:app" }
    langgraph_docker     = { index = "langgraph", sourcetype = "langgraph:app" }
    qdrant_docker        = { index = "qdrant", sourcetype = "qdrant:app" }
    docling_serve_docker = { index = "docling", sourcetype = "docling:app" }
    semaphore_docker     = { index = "semaphore", sourcetype = "semaphore:run" }
    clickhouse_docker    = { index = "clickhouse", sourcetype = "clickhouse:app" }
    phoenix_docker       = { index = "phoenix", sourcetype = "phoenix:app" }
  }

  ai_log_routing = {
    for name, port in local.ai_log_ports : name => {
      port       = port
      index      = local.ai_log_index_map[name].index
      sourcetype = local.ai_log_index_map[name].sourcetype
    }
  }
}
