locals {
  agent_systems = ["splunk", "cribl"]

  agent_firewall_profile_tags = setunion(
    toset(values(local.firewall_container_tags)),
    toset(local.pooled_backend_tags),
    toset(local.llm_cpu_scaler.pool_tags),
  )

  agent_unknown_system_slugs = sort(tolist(setsubtract(
    toset(flatten([for agent in values(var.agents) : agent.owns])),
    toset(local.agent_systems),
  )))

  agent_firewall_profile_conflicts = sort([
    for container_key, agent in var.agents : agent.name
    if length(setintersection(
      toset(coalesce(try(var.containers[container_key].tags, null), [])),
      toset(local.agent_firewall_profile_tags),
    )) > 0
  ])

  # Grouping (`...`) keeps a duplicate name from erroring here, so the
  # precondition below reports it instead.
  _agents_grouped = {
    for container_key, agent in var.agents : agent.name => merge(
      {
        container        = container_key
        hostname         = try(local.guest_hostname_containers[container_key], "")
        display          = agent.display
        purpose          = agent.purpose
        owns             = agent.owns
        router_key_class = agent.router_key_class
      },
      agent.slack == null ? {} : {
        slack = {
          for key, value in agent.slack : key => value
          if value != null
        }
      }
    )...
  }
  agents = { for name, entries in local._agents_grouped : name => entries[0] }
}

output "agents" {
  description = "Agent roster published in the Ansible inventory, keyed by agent name."
  value       = local.agents

  precondition {
    condition     = length(values(var.agents)) == length(distinct([for agent in values(var.agents) : agent.name]))
    error_message = "Agent names must be unique across the roster."
  }

  precondition {
    condition     = length(values(var.agents)) == length(distinct([for agent in values(var.agents) : agent.display]))
    error_message = "Agent displays must be unique across the roster."
  }

  precondition {
    condition     = length(flatten([for agent in values(var.agents) : agent.owns])) == length(distinct(flatten([for agent in values(var.agents) : agent.owns])))
    error_message = "Every agent owns value must be unique within and across agents."
  }

  precondition {
    condition     = length(setsubtract(keys(var.agents), keys(var.containers))) == 0
    error_message = "Agent roster keys must be container keys; unknown keys: ${jsonencode(setsubtract(keys(var.agents), keys(var.containers)))}."
  }

  precondition {
    condition     = length(local.agent_unknown_system_slugs) == 0
    error_message = "Agent owns values must name cataloged systems; unknown slugs: ${jsonencode(local.agent_unknown_system_slugs)}."
  }

  precondition {
    condition     = length(local.agent_firewall_profile_conflicts) == 0
    error_message = "Agent containers must not carry firewall-profile tags; offending agents: ${jsonencode(local.agent_firewall_profile_conflicts)}."
  }
}
