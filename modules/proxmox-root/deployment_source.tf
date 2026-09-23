# Desired-state object: the fetch, and the guards that reject a desired state
# which would produce a broken plan.
#
# Two sources, resolved to the same `local.deployment_body` string:
#   - the default: fetch the private RustFS object (unchanged behaviour).
#   - var.deployment_json: a caller passes the content directly (a git-tracked
#     desired-state repo, e.g. Vikunja 3492's homelab-live, committing
#     deployment.json and reading it with `file()`), skipping the S3 fetch
#     entirely. This is how the whole composition becomes usable as a module
#     from another repository's root while every existing caller — including
#     this repository's own root, one directory up — keeps working unchanged.
#
# Both guards below are postconditions/validations rather than `check` blocks:
# a failed `check` only WARNS (verified on the pinned OpenTofu 1.11 — the plan
# completes with exit 0), while a postcondition or a variable validation fails
# the plan hard. The S3 path's postconditions read self.body because a local
# derived from that data source cannot be referenced from its own lifecycle
# block; the deployment_json path mirrors the same four checks as variable
# validations, since there is no resource to hang a postcondition off of.
data "aws_s3_object" "deployment" {
  count = var.deployment_json == null ? 1 : 0

  bucket = var.deployment_bucket
  key    = var.deployment_key

  lifecycle {
    # Deployment contract: a truncated or half-written object would otherwise
    # proceed to plan the destruction of every guest it no longer mentions.
    postcondition {
      condition = (
        try(length(jsondecode(self.body).containers), 0) > 0 &&
        try(length(jsondecode(self.body).nodes), 0) > 0 &&
        try(length(jsondecode(self.body).pools), 0) > 0 &&
        try(jsondecode(self.body).proxmox_node, "") != "" &&
        try(jsondecode(self.body).domain, "") != "" &&
        try(length(jsondecode(self.body).network_cidrs), 0) > 0 &&
        try(jsondecode(self.body).vm_ssh_public_key, "") != ""
      )
      error_message = "The RustFS deployment object must contain non-empty containers, nodes, pools, proxmox_node, domain, network_cidrs, and vm_ssh_public_key before a plan can run. An empty or truncated object would otherwise plan the destruction of every guest it no longer mentions."
    }

    # A node_services per_node key that is not a key of `nodes` does not error:
    # the generator's `contains(keys(per_node), node_name)` filter simply skips
    # it, so the instance is SILENTLY DROPPED from the plan — the plan looks
    # fine, the guest just never exists. JSON Schema cannot express this
    # cross-sibling constraint.
    postcondition {
      condition = alltrue([
        for service_name, tmpl in try(jsondecode(self.body).node_services, {}) :
        length(setsubtract(keys(try(tmpl.per_node, {})), keys(try(jsondecode(self.body).nodes, {})))) == 0
      ])
      error_message = format(
        "node_services placement names node keys that do not exist in `nodes` — those instances would be silently dropped from the plan, not errored: %s. Fix the per_node key or add the node to `nodes`.",
        join("; ", [
          for service_name, tmpl in try(jsondecode(self.body).node_services, {}) :
          format(
            "template %q -> unknown node key(s) %s (known: %s)",
            service_name,
            jsonencode(setsubtract(keys(try(tmpl.per_node, {})), keys(try(jsondecode(self.body).nodes, {})))),
            jsonencode(keys(try(jsondecode(self.body).nodes, {}))),
          )
          if length(setsubtract(keys(try(tmpl.per_node, {})), keys(try(jsondecode(self.body).nodes, {})))) > 0
        ]),
      )
    }

    # ha_replication_target names the ONLY node a guest may be relocated to on
    # node loss, so a value that is not a real node, or that names the guest's
    # own home node, is worse than leaving it unset: it produces a relocation
    # target that holds no copy of the guest's data. The guest then fails to
    # start there and latches in an error state, on the one occasion the whole
    # mechanism exists for. Neither case can be expressed in JSON Schema, and
    # neither errors on its own — the consumer just builds a broken pair.
    postcondition {
      condition = length([
        for guest_key, guest in merge(
          try(jsondecode(self.body).containers, {}),
          try(jsondecode(self.body).vms, {}),
        ) : guest_key
        if try(guest.ha_replication_target, null) != null && (
          !contains(keys(try(jsondecode(self.body).nodes, {})), guest.ha_replication_target)
          || guest.ha_replication_target == try(guest.node_name, "")
        )
      ]) == 0
      error_message = format(
        "ha_replication_target must name a node in `nodes` that is NOT the guest's own node_name. Offending guests: %s. Known nodes: %s.",
        jsonencode([
          for guest_key, guest in merge(
            try(jsondecode(self.body).containers, {}),
            try(jsondecode(self.body).vms, {}),
          ) : format("%s -> %q (home %q)", guest_key, guest.ha_replication_target, try(guest.node_name, ""))
          if try(guest.ha_replication_target, null) != null && (
            !contains(keys(try(jsondecode(self.body).nodes, {})), guest.ha_replication_target)
            || guest.ha_replication_target == try(guest.node_name, "")
          )
        ]),
        jsonencode(keys(try(jsondecode(self.body).nodes, {}))),
      )
    }

    # Exactly one node may carry a given cluster role. Two claimants make the
    # consumer's "the node that does X" lookup pick one arbitrarily and stay
    # quiet about it; zero claimants make it resolve to nothing, which is the
    # failure mode of the environment-variable scheme this replaced.
    postcondition {
      condition = length([
        for role in ["storage"] : role
        if length([
          for node_key, node in try(jsondecode(self.body).nodes, {}) : node_key
          if contains(try(node.cluster_roles, []), role)
        ]) != 1
      ]) == 0
      error_message = format(
        "each cluster role must be claimed by exactly one node in `nodes`. Claimants: %s.",
        jsonencode({
          for role in ["storage"] : role => [
            for node_key, node in try(jsondecode(self.body).nodes, {}) : node_key
            if contains(try(node.cluster_roles, []), role)
          ]
        }),
      )
    }
  }
}

locals {
  deployment_body = var.deployment_json != null ? var.deployment_json : data.aws_s3_object.deployment[0].body

  # See variables.tf: empty keeps today's degrade-without-failing behaviour
  # for a caller that supplies deployment_json without its own etag.
  desired_state_etag = (
    var.desired_state_etag != null
    ? var.desired_state_etag
    : (var.deployment_json == null ? data.aws_s3_object.deployment[0].etag : "")
  )
}
