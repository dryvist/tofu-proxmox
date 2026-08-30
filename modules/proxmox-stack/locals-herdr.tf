# herdr LXCs. Two tag-driven sets, because the three guests do not share an
# egress profile and a single `herdr` tag would give the bridge and the UI the
# runtime's reach.
#
#   herdr_container_ids     — the runtime. Talks to model providers, package
#                             registries and git forges on behalf of every
#                             agent pane, so it needs broad outbound HTTPS.
#   herdr_client_container_ids — the Slack bridge and the web/phone dashboard.
#                             Both reach the runtime over SSH and, in the
#                             bridge's case, Slack over an outbound WebSocket.
#                             Neither needs the runtime's egress.
#
# Split into its own file for the same reason locals-hermes-ui.tf was: the
# shared 12 KB file-size gate on locals.tf.
locals {
  herdr_container_ids = {
    for k, v in var.containers : k => v.vm_id
    if contains(coalesce(try(v.tags, null), []), "herdr")
    && !contains(coalesce(try(v.tags, null), []), "herdr-slack")
    && !contains(coalesce(try(v.tags, null), []), "herdr-ui")
  }

  herdr_client_container_ids = {
    for k, v in var.containers : k => v.vm_id
    if contains(coalesce(try(v.tags, null), []), "herdr-slack")
    || contains(coalesce(try(v.tags, null), []), "herdr-ui")
  }
}
