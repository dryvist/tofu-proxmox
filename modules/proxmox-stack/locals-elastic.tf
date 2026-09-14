# elastic tag-filter local — kept out of locals.tf so that file stays under the
# shared _file-size workflow's 12 KB limit (locals merge across files in a
# module). Same split as locals-grafana.tf, whose shape this follows.
#
# The value is NOT a plain map(name -> vm_id): the cluster is a hot/hot PAIR on
# two nodes, and the firewall's default-deny resources are per-node — so each
# entry carries its guest's placement. elastic_rules.tf addresses its resources
# with each.value.node_name / each.value.vm_id, which is what actually lets the
# second peer (on a different host) be firewalled at all.
locals {
  elastic_container_ids = {
    for k, v in var.containers : k => {
      vm_id     = v.vm_id
      node_name = v.node_name
    }
    if contains(coalesce(try(v.tags, null), []), "elastic")
  }
}
