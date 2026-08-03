# Heavy-tier LLM serving host — identity supplied at apply time, never committed.
#
# This host is NOT a PVE guest. It is a fixed-address reservation owned by
# tofu-unifi, so it never appears in var.containers and cannot be derived the
# way every other host's address is (cidrhost(network_cidrs[vlan], vm_id)).
# That absence is the whole reason these two variables exist: without them the
# consuming repositories have nothing to read, which is how a literal ended up
# hand-copied into two public Ansible repositories in the first place.
#
# Both are supplied from the private deployment object at apply time, exactly
# like network_cidrs. The empty defaults are an ABSENCE SENTINEL, not a value —
# they exist so that a plan touching unrelated parts of the estate does not
# require the LLM fabric to be described, and they are deliberately not usable:
# consumers assert on emptiness and fail loudly rather than substituting a
# guess. There is no safe fallback for an address; a wrong one is worse than a
# missing one, because it fails as a timeout somewhere else entirely.

variable "llm_large_serving_host" {
  description = "Short hostname of the heavy-tier LLM serving host (a tofu-unifi reservation, not a PVE guest). Supplied from the private deployment object; empty means 'not described', which consumers must treat as a hard error rather than guessing."
  type        = string
  default     = ""
}

variable "llm_large_serving_ip" {
  description = "Reserved address of the heavy-tier LLM serving host. Supplied from the private deployment object (sensitive, never committed); empty means 'not described', which consumers must treat as a hard error rather than guessing."
  type        = string
  sensitive   = true
  default     = ""

  validation {
    condition     = var.llm_large_serving_ip == "" || can(cidrhost("${var.llm_large_serving_ip}/32", 0))
    error_message = "llm_large_serving_ip must be a bare IPv4 address (no mask) or empty."
  }
}
