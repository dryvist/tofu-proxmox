# hermes-ui LXC (hermes-ui tag): a companion web UI guest for the Hermes
# agent — its own tag, separate from hermes-agent, so its egress can be
# tightened later without touching the agent profile. Split out of
# locals.tf so that file stays under the shared _file-size 12 KB gate, the
# same reason locals-llm-fabric.tf was split out.
locals {
  hermes_ui_container_ids = {
    for k, v in var.containers : k => v.vm_id
    if contains(coalesce(try(v.tags, null), []), "hermes-ui")
  }
}
