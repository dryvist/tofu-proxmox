# Board presentation for ingress routes. Only the exceptions live here.
#
#   ui      = sso by default — machine clients can do neither a browser login
#             nor anything a person opens. Exceptions listed below.
#   section = derived: a guest serving 2+ routes is a section (backends.tf).
#   desc    = the guest's `summary` in deployment.json; the map below covers
#             pool/apex routes that have no guest.
#
# Same shape as locals-ingress-groups.tf: inherit from the guest, list only
# what cannot. Replaces a 55-entry description table, an 18-entry deny-list
# and a 12-entry section map.
locals {
  # Human UIs that skip the gate because their clients authenticate natively —
  # the only routes where ui and sso disagree.
  ingress_human_unauthed_routes = toset([
    "plex",
    "vikunja",
    "homeassistant",
    "proxmox",
  ])

  # Routes with no owning guest to inherit a summary from: load-balanced pools,
  # the apex, and the VM-backed routes (a VM is not in var.containers).
  ingress_pool_descriptions = {
    agentgateway   = "MCP fabric admin UI"
    hindsight      = "Agent long-term memory API"
    "hindsight-cp" = "Agent memory control plane"
    llm            = "OpenAI-compatible model router"
    mcp            = "MCP tool proxy"
    openbao        = "Secrets management"
    otel           = "OTLP trace ingest"
    proxmox        = "Hypervisor cluster UI"
    zammad         = "Incident and ticket tracking"

    # Splunk VM.
    splunk        = "Log search and analytics"
    "splunk-mgmt" = "Splunk management REST API"
    "splunk-hec"  = "Splunk HTTP event collector"

    # iac-platform VM.
    terrakube            = "OpenTofu run platform"
    "terrakube-api"      = "Terrakube API"
    "terrakube-registry" = "Terrakube module registry"
    "terrakube-dex"      = "Terrakube OIDC provider"
    semaphore            = "Ansible run platform"
  }
}
