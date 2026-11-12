# Crawl4AI guest firewall selection (crawl4ai tag). Keeping its service map
# separate from the shared AI-orchestration map gives it a dedicated API rule.
locals {
  crawl4ai_container_ids = {
    for k, v in var.containers : k => v.vm_id
    if contains(coalesce(try(v.tags, null), []), local.firewall_container_tags.crawl4ai)
  }
}
