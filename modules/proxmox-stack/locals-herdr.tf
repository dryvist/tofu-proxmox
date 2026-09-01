# herdr LXCs. Two tag-driven sets, because the guests do not share an egress
# profile and a single `herdr` tag would give the dashboard the runtime's reach.
#
#   herdr_container_ids        — the runtime. Talks to model providers, package
#                                registries and git forges on behalf of every
#                                agent pane, so it needs broad outbound HTTPS.
#                                It also carries the Slack bridge, which is a
#                                herdr plugin reading the local control socket,
#                                not a guest of its own.
#   herdr_client_container_ids — the web/phone dashboard. Reaches the runtime
#                                over SSH and needs none of its egress.
#
# Split into its own file for the same reason locals-hermes-ui.tf was: the
# shared 12 KB file-size gate on locals.tf.
locals {
  herdr_container_ids = {
    for k, v in var.containers : k => v.vm_id
    if contains(coalesce(try(v.tags, null), []), "herdr")
    && !contains(coalesce(try(v.tags, null), []), "herdr-ui")
  }

  herdr_client_container_ids = {
    for k, v in var.containers : k => v.vm_id
    if contains(coalesce(try(v.tags, null), []), "herdr-ui")
  }
}
