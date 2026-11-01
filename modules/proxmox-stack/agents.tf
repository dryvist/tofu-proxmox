locals {
  # Existing physical agents keep their container-key input and legacy name.
  # Logical owners use the input map key as their stable owner key.
  agent_owner_keys = {
    for input_key, agent in var.agents : input_key => agent.name == null ? input_key : agent.name
  }

  agent_physical_container_keys = [
    for input_key, agent in var.agents : input_key
    if agent.name != null
  ]

  agent_unknown_physical_container_keys = sort(tolist(setsubtract(
    toset(local.agent_physical_container_keys),
    toset(keys(var.containers)),
  )))

  # Firewall ownership remains limited to the services with configured ports
  # and destination hosts below. The published `owns` roster remains open-ended.
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
    splunk = concat(
      [split("/", local.splunk_derived_ip)[0]],
      [
        for container_key, ipv4 in local.container_ipv4 : split("/", ipv4)[0]
        if ipv4 != "dhcp" && contains(coalesce(var.containers[container_key].tags, []), local.firewall_container_tags.splunk)
      ],
    )
    cribl = [
      for container_key in keys(local.cribl_stream_container_ids) : split("/", local.container_ipv4[container_key])[0]
      if local.container_ipv4[container_key] != "dhcp"
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

  agent_firewall_profile_conflicts = sort([
    for container_key, agent in var.agents : agent.name
    if agent.name != null && length(setintersection(
      toset(coalesce(try(var.containers[container_key].tags, null), [])),
      toset(local.agent_firewall_profile_tags),
    )) > 0
  ])

  # Grouping (`...`) keeps a logical key that collides with a physical name
  # from erroring here, so the precondition below reports it instead.
  _agents_grouped = {
    for input_key, agent in var.agents : local.agent_owner_keys[input_key] => merge(
      {
        display          = agent.display
        purpose          = agent.purpose
        owns             = agent.owns
        router_key_class = agent.router_key_class
        trust_tier       = agent.trust_tier == null ? "untrusted" : agent.trust_tier
      },
      agent.name == null ? {} : {
        container = input_key
        hostname  = try(local.guest_hostname_containers[input_key], "")
      },
      agent.native_binding_ref == null ? {} : {
        native_binding_ref = agent.native_binding_ref
      },
      agent.name == null || agent.specializations != null ? {
        specializations = agent.specializations == null ? [] : agent.specializations
      } : {},
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
      vm_id = try(var.containers[agent.container].vm_id, null)
      owns = tolist([
        for slug in agent.owns : slug
        if contains(keys(local.agent_system_port_catalog), slug)
      ])
    }
    if try(agent.container, null) != null && contains(keys(var.containers), try(agent.container, ""))
  }
}

output "agents" {
  description = "Agent roster published in the Ansible inventory, keyed by agent name."
  value       = local.agents

  precondition {
    condition     = length(values(var.agents)) == length(distinct(values(local.agent_owner_keys)))
    error_message = "Agent owner keys must be unique across physical and logical owners."
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
    condition     = length(local.agent_unknown_physical_container_keys) == 0
    error_message = "Physical agent roster keys must be existing container keys; unknown keys: ${jsonencode(local.agent_unknown_physical_container_keys)}."
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
        ) if contains(local.agent_systems, slug)
      ] if agent.name != null
    ]))
    error_message = "owned systems need static host addresses for agent firewall rules."
  }

  precondition {
    condition     = length(local.agent_firewall_profile_conflicts) == 0
    error_message = "Agent containers must not carry firewall-profile tags; offending agents: ${jsonencode(local.agent_firewall_profile_conflicts)}."
  }
}
