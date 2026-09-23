variable "openbao_kv_mount" {
  description = "OpenBao KV v2 mount used by Terrakube workspaces"
  type        = string
  default     = "secret"
}

variable "openbao_object_storage_path" {
  description = "Native OpenBao KV path containing RustFS S3 endpoint and credentials"
  type        = string
  default     = "platform/object-storage"
}

variable "openbao_proxmox_path" {
  description = "Native OpenBao KV path containing Proxmox API and SSH credentials"
  type        = string
  default     = "infrastructure/proxmox"
}

variable "deployment_bucket" {
  description = "RustFS bucket containing private desired state. Unused when deployment_json is set."
  type        = string
  default     = "iac-inventory"
}

variable "deployment_key" {
  description = "RustFS object key containing private desired state. Unused when deployment_json is set."
  type        = string
  default     = "deployment.json"
}

# The module-callable escape hatch (Vikunja 3492): a caller that already
# holds deployment.json's content (e.g. read via `file()` in a git-tracked
# desired-state repo) passes it here instead of this module fetching the
# RustFS object itself. Every existing caller leaves this unset and keeps
# today's S3-fetch behaviour unchanged — see deployment_source.tf.
variable "deployment_json" {
  description = "Raw deployment.json content. When set, this is decoded directly and the RustFS fetch (deployment_bucket/deployment_key) is skipped. Validated against the same contract as the fetched object (see deployment_source.tf's postconditions, mirrored below since a variable has no lifecycle block to hang a postcondition off of)."
  type        = string
  default     = null

  validation {
    condition = (
      var.deployment_json == null || (
        try(length(jsondecode(var.deployment_json).containers), 0) > 0 &&
        try(length(jsondecode(var.deployment_json).nodes), 0) > 0 &&
        try(length(jsondecode(var.deployment_json).pools), 0) > 0 &&
        try(jsondecode(var.deployment_json).proxmox_node, "") != "" &&
        try(jsondecode(var.deployment_json).domain, "") != "" &&
        try(length(jsondecode(var.deployment_json).network_cidrs), 0) > 0 &&
        try(jsondecode(var.deployment_json).vm_ssh_public_key, "") != ""
      )
    )
    error_message = "deployment_json must contain non-empty containers, nodes, pools, proxmox_node, domain, network_cidrs, and vm_ssh_public_key before a plan can run. An empty or truncated object would otherwise plan the destruction of every guest it no longer mentions."
  }

  validation {
    condition = (
      var.deployment_json == null || alltrue([
        for service_name, tmpl in try(jsondecode(var.deployment_json).node_services, {}) :
        length(setsubtract(keys(try(tmpl.per_node, {})), keys(try(jsondecode(var.deployment_json).nodes, {})))) == 0
      ])
    )
    error_message = "deployment_json.node_services names a per_node key that is not a key of `nodes` — that instance would be silently dropped from the plan, not errored. Fix the per_node key or add the node to `nodes`."
  }

  validation {
    condition = (
      var.deployment_json == null || length([
        for guest_key, guest in merge(
          try(jsondecode(var.deployment_json).containers, {}),
          try(jsondecode(var.deployment_json).vms, {}),
        ) : guest_key
        if try(guest.ha_replication_target, null) != null && (
          !contains(keys(try(jsondecode(var.deployment_json).nodes, {})), guest.ha_replication_target)
          || guest.ha_replication_target == try(guest.node_name, "")
        )
      ]) == 0
    )
    error_message = "deployment_json: ha_replication_target must name a node in `nodes` that is NOT the guest's own node_name."
  }

  validation {
    condition = (
      var.deployment_json == null || length([
        for role in ["storage"] : role
        if length([
          for node_key, node in try(jsondecode(var.deployment_json).nodes, {}) : node_key
          if contains(try(node.cluster_roles, []), role)
        ]) != 1
      ]) == 0
    )
    error_message = "deployment_json: each cluster role must be claimed by exactly one node in `nodes`."
  }
}

# Published into the Ansible inventory as desired_state.etag (see
# modules/proxmox-stack/variables-infrastructure.tf); purely informational —
# empty degrades the downstream freshness check rather than failing it. When
# unset (null): the RustFS object's own ETag for the S3 path (unchanged
# behaviour), or empty for the deployment_json path, since there is no ETag
# to report. A caller may always pass its own value instead — e.g. its git
# commit SHA — which is more meaningful than an S3 ETag for a git-tracked
# desired state.
variable "desired_state_etag" {
  description = "Override for the published desired_state.etag. Defaults to the RustFS object's ETag on the S3 path, or empty on the deployment_json path."
  type        = string
  default     = null
}

# Bakes the OpenBao SSH client CA into new guests' cloud-init vendor-data.
# Left at the default, this is a no-op.
variable "ssh_ca_trust_rollout_enabled" {
  description = "Bake OpenBao SSH-CA trust into new guests' cloud-init vendor-data via ssh-client-ca/config/ca (read on the workspace's own OpenBao identity)."
  type        = bool
  default     = false
}

variable "openbao_accept_quorum_loss_on_node_failure" {
  description = "Acknowledge that the planned OpenBao voter placement may not survive a one-node loss (cluster at or below Raft quorum). Only for a deliberate degraded maintenance window; default false. Passed through to the proxmox-stack voter-spread guard."
  type        = bool
  default     = false
}

variable "inventory_bucket" {
  description = "RustFS bucket receiving the published Ansible inventory"
  type        = string
  default     = "iac-inventory"
}

variable "inventory_key" {
  description = "RustFS object key receiving the published Ansible inventory"
  type        = string
  default     = "ansible_inventory.json"
}
