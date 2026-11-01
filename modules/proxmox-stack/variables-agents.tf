variable "agents" {
  description = "Agent owner roster: physical entries remain keyed by container key; logical entries use an owner slug key."
  type = map(object({
    name               = optional(string)
    display            = string
    purpose            = string
    owns               = optional(list(string), [])
    router_key_class   = optional(string, "standard")
    trust_tier         = optional(string)
    native_binding_ref = optional(string)
    specializations = optional(list(object({
      name        = string
      description = string
    })))
    slack = optional(object({
      home_channel     = optional(string)
      requests_channel = optional(string)
    }))
  }))
  default = {}

  validation {
    condition = alltrue([
      for agent_key, agent in var.agents :
      (
        agent.name == null
        ? can(regex("^[a-z][a-z0-9-]*$", agent_key))
        : can(regex("^[a-z]+-[a-z]+$", agent.name))
      )
      &&
      length(agent.display) > 0 &&
      length(agent.purpose) > 0 &&
      contains(["all", "standard", "zdr"], agent.router_key_class) &&
      (
        agent.trust_tier == null ||
        try(contains(["trusted", "untrusted"], agent.trust_tier), false)
      ) &&
      (
        agent.native_binding_ref == null ||
        try(
          length(trimspace(agent.native_binding_ref)) > 0,
          false
        )
      ) &&
      (
        agent.name != null ? true : (
          agent.trust_tier != null &&
          try(contains(["trusted", "untrusted"], agent.trust_tier), false) &&
          try(
            length(trimspace(agent.native_binding_ref)) > 0,
            false
          )
        )
      ) &&
      alltrue([for owned in agent.owns : can(regex("^[a-z][a-z0-9-]*$", owned))]) &&
      (
        agent.specializations == null ? true : try(
          alltrue([
            for specialization in agent.specializations : (
              can(regex("^[a-z][a-z0-9-]*$", specialization.name)) &&
              length(trimspace(specialization.description)) > 0
            )
          ]) &&
          length([for specialization in agent.specializations : specialization.name]) ==
          length(distinct([for specialization in agent.specializations : specialization.name])),
          false
        )
      )
    ])
    error_message = "Physical agents keep a <function>-<persona> name; logical owners omit name and use an owner slug key. Every owner needs a non-empty display and purpose, valid owns slugs, and a valid router_key_class. Logical owners also need an explicit valid trust_tier and a nonblank native_binding_ref. Specialization names must be unique slugs with non-empty descriptions."
  }
}
