# Dashboard groups for the ingress routes that have no backend container.
#
# Every estate board (Homarr, Homepage, Glance) renders from the one published
# ingress list, so each route needs exactly one group and it is set exactly
# once. A container-backed route inherits its backend's `vlan` in
# locals-ingress-backends.tf — the VLAN is already an accurate, already-kept
# statement of what a guest is, so grouping needs no second tag list and a new
# guest is filed on all three boards by being given a VLAN and a route.
#
# The routes below are the exceptions: load-balanced pools and VM-backed routes
# resolve their address from a backend list or a VM FQDN rather than from
# var.containers, so there is no VLAN to inherit and the group is stated here.
# Anything absent falls back to "other" rather than failing — a new route shows
# up on the boards in a catch-all group instead of silently vanishing from them.
#
# Split into its own file so locals-ingress-backends.tf stays under the shared
# _file-size 12 KB error threshold; locals merge across files in the module.

locals {
  ingress_route_groups = {
    # Observability / SIEM tier — the Splunk VM's three routes plus the Cribl
    # OTLP receiver pool.
    splunk        = "siem"
    "splunk-mgmt" = "siem"
    "splunk-hec"  = "siem"
    otel          = "siem"

    # Platform / management.
    proxmox              = "mgmt"
    openbao              = "mgmt"
    terrakube            = "mgmt"
    "terrakube-api"      = "mgmt"
    "terrakube-registry" = "mgmt"
    "terrakube-dex"      = "mgmt"
    semaphore            = "mgmt"

    # AI tier pools.
    llm            = "ai"
    mcp            = "ai"
    agentgateway   = "ai"
    hindsight      = "ai"
    "hindsight-cp" = "ai"

    # Apps tier pools.
    zammad = "apps"
  }
}
