variable "agents" {
  description = "Agent roster keyed by the container key each agent runs in."
  type = map(object({
    name             = string
    display          = string
    purpose          = string
    owns             = optional(list(string), [])
    router_key_class = optional(string, "standard")
    trust_tier       = optional(string, "untrusted")
    slack = optional(object({
      home_channel     = optional(string)
      requests_channel = optional(string)
    }))
  }))
  default = {}

  validation {
    condition = alltrue([
      for agent in values(var.agents) : (
        can(regex("^[a-z]+-[a-z]+$", agent.name)) &&
        length(agent.display) > 0 &&
        length(agent.purpose) > 0 &&
        contains(["all", "standard", "zdr"], agent.router_key_class) &&
        contains(["trusted", "untrusted"], agent.trust_tier) &&
        alltrue([for owned in agent.owns : can(regex("^[a-z][a-z0-9-]*$", owned))])
      )
    ])
    error_message = "Each agent requires a name matching <function>-<persona>, non-empty display and purpose, owns slugs matching [a-z][a-z0-9-]*, router_key_class all, standard, or zdr, and trust_tier trusted or untrusted."
  }
}
