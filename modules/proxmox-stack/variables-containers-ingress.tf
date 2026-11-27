# Container variables: tagged-ingress validation
#
# Moved from variables-containers.tf, which was at the per-file size limit.
# The tagged keys are the ingress load-balanced pool backends (ingress.tf);
# if exactly one of them is tagged 'agentgateway' the tagged ingress is left
# half-wired, so the plan fails instead.

variable "containers" {
  validation {
    condition = !anytrue([
      for c in values(var.containers) : try(contains(c.tags, "agentgateway"), false)
      ]) || alltrue([
      for k in ["agentgateway", "agentgateway-2"] :
      try(contains(var.containers[k].tags, "agentgateway"), false)
    ])
    error_message = "Tagged ingress requires both selected keys tagged 'agentgateway'."
  }
}
