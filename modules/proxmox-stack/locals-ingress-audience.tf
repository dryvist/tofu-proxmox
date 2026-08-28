# Ingress route AUDIENCE + presentation metadata.
#
# The dashboards need to answer three questions the route table alone cannot:
#
#   ui      — is this a surface a PERSON opens, or a machine endpoint? A board
#             that mixes a bearer-token job API in with the apps a human clicks
#             is noise. `sso` is NOT a usable proxy for this: Plex, Vikunja and
#             Home Assistant are all human UIs that opt OUT of the Authelia gate
#             because their own clients authenticate natively.
#   section — an optional sub-grouping INSIDE a group, so one guest's many
#             routes (Hermes publishes five per agent) read as one block rather
#             than scattering through the AI list.
#   desc    — a one-line description rendered beside the link.
#
# These live in their own file rather than inline on each row because
# `ingress.tf` is already 8 KB against the shared 12 KB file-size gate, and a
# description on every row would cross it. Locals merge across files.
#
# DRIFT IS FAIL-LOUD: `checks.tf` has no teeth (a failed check only warns), so
# the assertion that every route carries a description is a precondition on the
# inventory publish instead — see locals-ingress-backends.tf.
locals {
  # Routes a PERSON does not open in a browser: machine APIs, ingest endpoints,
  # webhook receivers, auth plumbing. Everything not listed here is a UI.
  # Deny-list rather than allow-list on purpose: a NEW route defaults to being
  # visible, so a service can never be silently missing from the boards — the
  # failure mode is a machine endpoint showing up in the human column, which is
  # obvious on sight and cheap to fix.
  ingress_machine_routes = toset([
    "authelia",         # the login page itself, not a destination
    "docling-serve",    # Open WebUI's OCR backend
    "hindsight",        # agent memory API
    "langgraph",        # dev-server API
    "llm",              # OpenAI-compatible router
    "mcp",              # MCP proxy plane
    "nautobot-api",     # token-auth REST
    "nautobot-graphql", # token-auth GraphQL
    "ntfy",             # publish endpoint
    "otel",             # OTLP span ingest
    "qdrant",           # vector API
    "s3",               # S3 API
    "splunk-hec",       # HEC ingest
    "splunk-mgmt",      # splunkd REST
    "terrakube-api",    # Terrakube REST
    "terrakube-dex",    # OIDC provider
    "terrakube-registry",
    "honeypot-notify", # machine notify API
  ])

  # Sub-grouping inside a group. Every Hermes route collapses into one "Hermes"
  # block under AI; the per-agent split stays visible in the link titles.
  ingress_route_sections = merge(
    { for k, _ in local.hermes_agent_routes : k => "Hermes" },
    {
      "hermes-ui"          = "Hermes"
      "mission-control"    = "Hermes"
      "terrakube"          = "Terrakube"
      "terrakube-api"      = "Terrakube"
      "terrakube-dex"      = "Terrakube"
      "terrakube-registry" = "Terrakube"
      "splunk"             = "Splunk"
      "splunk-hec"         = "Splunk"
      "splunk-mgmt"        = "Splunk"
      "nautobot"           = "Nautobot"
      "nautobot-api"       = "Nautobot"
      "nautobot-graphql"   = "Nautobot"
    },
  )

  # One line per route, rendered beside the link on every board. Generated
  # Hermes routes get theirs from the same generator that makes the route, so
  # adding an agent needs no edit here.
  ingress_route_descriptions = merge(local.hermes_route_descriptions, {
    agentgateway         = "MCP fabric admin UI"
    authelia             = "SSO login portal"
    chat                 = "Open WebUI — chat over every routed model"
    dify                 = "LLM app builder"
    "docling-serve"      = "Document OCR and layout extraction"
    "docs-static"        = "Static documentation host"
    glance               = "This board"
    "haproxy-stats"      = "Load-balancer statistics"
    hindsight            = "Agent long-term memory API"
    "hindsight-cp"       = "Agent memory control plane"
    homarr               = "Service dashboard (hand-arranged)"
    homeassistant        = "Home automation"
    homepage             = "Service dashboard (auto-generated)"
    "honeypot-notify"    = "Deception-fabric alert relay"
    langflow             = "Visual LLM flow builder"
    langfuse             = "LLM tracing and evaluation"
    langgraph            = "LangGraph dev-server API"
    "langgraph-chat"     = "LangGraph agent chat"
    llm                  = "OpenAI-compatible model router"
    mailpit              = "Captured outbound mail"
    mcp                  = "MCP tool proxy"
    "mission-control"    = "OpenClaw mission control"
    n8n                  = "Workflow automation"
    nautobot             = "Network source of truth"
    "nautobot-api"       = "Nautobot REST API"
    "nautobot-graphql"   = "Nautobot GraphQL API"
    ntfy                 = "Push notification endpoint"
    "object-storage"     = "Object storage console"
    openbao              = "Secrets management"
    openproject          = "Project management"
    otel                 = "OTLP trace ingest"
    phpipam              = "IP address management"
    plex                 = "Media library"
    prometheus           = "Metrics and alerting"
    prowlarr             = "Indexer manager"
    proxmox              = "Hypervisor cluster UI"
    qbittorrent          = "Download client"
    qdrant               = "Vector database API"
    radarr               = "Film library manager"
    s3                   = "S3-compatible object API"
    seerr                = "Media requests"
    semaphore            = "Ansible run platform"
    smokeping            = "Network latency graphs"
    sonarr               = "Series library manager"
    sortarr              = "Media sorting"
    splunk               = "Log search and analytics"
    "splunk-hec"         = "Splunk HTTP event collector"
    "splunk-mgmt"        = "Splunk management API"
    technitium           = "Internal DNS"
    terrakube            = "OpenTofu run platform"
    "terrakube-api"      = "Terrakube REST API"
    "terrakube-dex"      = "Terrakube OIDC provider"
    "terrakube-registry" = "Terrakube module registry"
    vikunja              = "Task and Kanban tracking"
    zammad               = "Incident and ticket tracking"
  })
}
