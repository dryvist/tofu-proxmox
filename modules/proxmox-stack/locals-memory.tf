# Database + agent-memory tag-filter locals — split from locals.tf to keep it
# under the shared _file-size workflow's 12 KB gate (locals merge across files
# in the module, same split as locals-honeypot.tf / locals-ingress-backends.tf).
locals {
  # Postgres LXCs — the shared native cluster ("postgres" tag) plus the ai-VLAN
  # memory cluster ("postgres_ai" tag; primary + streaming standby backing
  # Hindsight). Both take the same postgres-svc firewall shape (5432 from
  # internal); Ansible grouping stays separate via the distinct tags.
  postgres_container_ids = {
    for k, v in var.containers : k => v.vm_id
    if length(setintersection(toset(coalesce(try(v.tags, null), [])), toset([local.firewall_container_tags.postgres, local.firewall_container_tags.postgres_ai]))) > 0
  }

  # Hindsight agent-memory containers (hindsight tag) — stateless API replicas.
  hindsight_container_ids = {
    for k, v in var.containers : k => v.vm_id
    if contains(coalesce(try(v.tags, null), []), local.firewall_container_tags.hindsight)
  }
}
