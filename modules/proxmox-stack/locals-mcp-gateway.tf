# MCP gateway tag-filter local — extracted from locals.tf so that file stays
# under the shared _file-size workflow's 12 KB limit. Same split as
# locals-vikunja.tf. Consumed by the firewall module call in main.tf.

locals {
  # MCP gateway LXC (mcp-gateway tag) — single HTTP/SSE endpoint (IBM
  # mcp-context-forge) every MCP client reaches, on mcp_gateway_web (4444).
  # modules/firewall opens 4444 to it from internal.
  mcp_gateway_container_ids = {
    for k, v in var.containers : k => v.vm_id
    if contains(coalesce(try(v.tags, null), []), "mcp-gateway")
  }
}
