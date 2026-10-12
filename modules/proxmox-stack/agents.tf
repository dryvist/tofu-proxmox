locals {
  agent_systems = ["splunk", "cribl"]

  # System service ports agents may own. Values resolve from the shared
  # pipeline constants; the keys stay aligned with agent_systems below.
  agent_system_port_catalog = {
    splunk = [
      local.pipeline_constants.service_ports.splunk_mgmt,
      local.pipeline_constants.service_ports.splunk_web,
    ]
    cribl = [local.pipeline_constants.service_ports.cribl_stream_api]
  }

  agent_system_hosts = {
    splunk = local.splunk_network_ips
    cribl = [
      for container_key, vm_id in local.cribl_stream_container_ids : nonsensitive(
        cidrhost(var.network_cidrs[var.containers[container_key].vlan], vm_id)
      ) if !var.containers[container_key].dhcp
    ]
  }

  agent_system_dhcp_members = {
    splunk = [
      for container_key, container in var.containers : container_key
      if contains(coalesce(container.tags, []), local.firewall_container_tags.splunk) && container.dhcp
    ]
    cribl = [
      for container_key in keys(local.cribl_stream_container_ids) : container_key
      if var.containers[container_key].dhcp
    ]
  }

  # Profile tags checked only by variable validations in
  # variables-containers.tf, which cannot read locals.
  agent_validation_profile_tags = ["ai-runner", "hermes-donna"]

  agent_firewall_profile_tags = setunion(
    toset(values(local.firewall_container_tags)),
    toset(local.agent_validation_profile_tags),
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

  agent_firewall_containers = {
    for name, agent in local.agents : name => {
      # Keep invalid container references available to the roster output
      # precondition instead of failing during local projection.
      vm_id = try(var.containers[agent.container].vm_id, null)
      owns  = agent.owns
    }
  }
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
    condition = (
      toset(keys(local.agent_system_port_catalog)) == toset(local.agent_systems) &&
      toset(keys(local.agent_system_hosts)) == toset(local.agent_systems)
    )
    error_message = "The agent system port and host catalog keys must match agent_systems."
  }

  precondition {
    condition = alltrue(flatten([
      for agent in values(var.agents) : [
        for slug in agent.owns : (
          length(try(local.agent_system_hosts[slug], [])) > 0 &&
          length(try(local.agent_system_dhcp_members[slug], [])) == 0
        )
      ]
    ]))
    error_message = "owned systems need static host addresses for agent firewall rules."
  }

  precondition {
    condition     = length(local.agent_firewall_profile_conflicts) == 0
    error_message = "Agent containers must not carry firewall-profile tags; offending agents: ${jsonencode(local.agent_firewall_profile_conflicts)}."
  }
}
