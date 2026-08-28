# Tag-generated Traefik routes, one set per Hermes agent guest.
#
# These rows used to be hand-listed in ingress.tf: a dashboard/webhook/api
# triplet for hermes-agent plus a separate hand-added row for hermes-donna.
# Agent #3 meant four more hand edits, and the agent count is expected to keep
# growing, so the set is derived from local.hermes_agent_container_ids (the
# hermes-agent tag) instead. Adding an agent to the desired state now publishes
# its whole route set with no change here.
#
# Split into its own file so ingress.tf stays under the shared _file-size
# workflow's 12 KB gate — same reason locals-hermes-ui.tf was split out. Locals
# merge across files in a module, so this is a pure relocation of the mechanism.

locals {
  # Hostname overrides, keyed by container. An agent's routes default to its
  # container key, but hermes-agent's dashboard is long-published at
  # `hermes`, and that hostname is LOAD-BEARING: the Hermes dashboard rebuilds
  # its OIDC redirect_uri from the statically configured public_url rather than
  # from the request Host, so renaming the route silently breaks login (proved
  # in the #742 revert). New agents need no entry.
  hermes_route_hostnames = {
    "hermes-agent" = "hermes"
  }

  # Agent display name for the board. coalesce, not a try chain: an unset
  # optional attribute is null, which try returns rather than falling through.
  hermes_route_agent_name = {
    for k, _ in local.hermes_agent_container_ids :
    k => coalesce(try(var.containers[k].summary, ""), k)
  }

  # Per-route descriptions. Without these every route on an agent guest
  # inherits that guest's single `summary`, so all five read identically on the
  # boards. The agent name comes from the summary; only the role differs.
  hermes_route_roles = {
    ""          = "agent dashboard"
    "-webhooks" = "webhook receiver"
    "-api"      = "job submission API"
    "-webui"    = "hermes-webui"
    "-studio"   = "hermes-studio"
  }

  # Per-agent route set. Every generated name is a SINGLE label: the wildcard
  # certificate covers one level below the ingress subdomain, so a dot in a
  # route name would put the host outside it.
  #
  # Browser surfaces take the default SSO gate (sso omitted => true). The
  # webhook receiver and the job API opt out: their callers are machines that
  # authenticate natively (HMAC signature / bearer token) and cannot complete a
  # browser login.
  hermes_agent_routes = merge([
    for k, _ in local.hermes_agent_container_ids : {
      # Interactive Dashboard — owns the host root.
      (k) = {
        hostname = try(local.hermes_route_hostnames[k], k)
        backend  = k
        port     = local.pipeline_constants.service_ports.hermes_dashboard
        desc     = "${local.hermes_route_agent_name[k]} — ${local.hermes_route_roles[""]}"
      }
      # Webhook receiver — keeps its established path on the dashboard's host.
      "${k}-webhooks" = {
        hostname    = try(local.hermes_route_hostnames[k], k)
        path_prefix = "/webhooks/"
        priority    = 100
        backend     = k
        port        = local.pipeline_constants.service_ports.hermes_webhook
        desc        = "${local.hermes_route_agent_name[k]} — ${local.hermes_route_roles["-webhooks"]}"
        sso         = false # HMAC-signed webhooks
      }
      # Job-submission API (`hermes gateway` api_server platform).
      "${k}-api" = {
        hostname = "${try(local.hermes_route_hostnames[k], k)}-api"
        backend  = k
        port     = local.pipeline_constants.service_ports.hermes_api
        desc     = "${local.hermes_route_agent_name[k]} — ${local.hermes_route_roles["-api"]}"
        sso      = false # bearer-authenticated job API
      }
      # The two co-located third-party UIs (see constants.tf for why they run
      # on the agent guest rather than in one of their own).
      "${k}-webui" = {
        hostname = "${try(local.hermes_route_hostnames[k], k)}-webui"
        backend  = k
        port     = local.pipeline_constants.service_ports.hermes_webui
        desc     = "${local.hermes_route_agent_name[k]} — ${local.hermes_route_roles["-webui"]}"
      }
      "${k}-studio" = {
        hostname = "${try(local.hermes_route_hostnames[k], k)}-studio"
        backend  = k
        port     = local.pipeline_constants.service_ports.hermes_studio
        desc     = "${local.hermes_route_agent_name[k]} — ${local.hermes_route_roles["-studio"]}"
      }
    }
  ]...)

  # Every Hermes agent's OpenAI-compatible endpoint, published to the Ansible
  # inventory. This is what lets ONE Open WebUI be the single pane over every
  # agent: the consuming role creates one connection per entry, and each agent
  # then appears as its own selectable model. Adding an agent to the desired
  # state wires it up with no edit here and no second login — which is the whole
  # point, since the agents' own dashboards are machine-level and have no fleet
  # view.
  #
  # The /v1 suffix is part of the contract, not decoration: Open WebUI's
  # connection test passes without it and then lists no models at all, which is
  # the most common way this integration looks configured but is not.
  #
  # Only the address is published. Each agent's API_SERVER_KEY is read from the
  # secret store by the consuming role; no credential belongs in this artifact.
  hermes_agents_inventory = {
    for k, _ in local.hermes_agent_container_ids : k => {
      api_url    = "http://${local.container_address[k]}:${local.pipeline_constants.service_ports.hermes_api}/v1"
      model_name = k
    }
  }
}
