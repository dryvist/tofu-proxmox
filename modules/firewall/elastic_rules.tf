# Elastic Stack LXC firewall — the cluster spans TWO hosts as a
# hot/hot pair, so its guest-set carries placement. Unlike every other rule
# file in this module (which all key off a single module-level node_name), the
# elastic resources address each guest on the node it actually lives on
# (each.value.node_name / each.value.vm_id). This is the first multi-node
# guest-set in the estate; the map(object({vm_id, node_name})) contract is
# deliberate (see variables-guest-sets.tf).
#
# Live guest-layer rules, default-deny per-service allow model:
#   elastic_http     (9200) — REST/API + Cribl ingests; internal-only, never
#                              fronted by Traefik (the ES API stays off the
#                              web ingress).
#   elastic_transport (9300) — node-to-node cluster traffic between the two
#                              peers (discovery + shard replication).
#   kibana_web        (5601) — Kibana UI, reached through Traefik (ingress)
#                              and SSO-gated.
#
# Egress: internal, plus HTTPS/HTTP. HTTPS is load-bearing — the compose stack
# pulls its pinned images from docker.elastic.co at converge time (not in the
# Zot mirror list, which is docker.io/ghcr.io/quay.io only).
locals {
  elastic_services_rules = [
    { proto = "tcp", dport = tostring(local.svc_ports.elastic_http), source = local.internal_src, comment = "Elasticsearch REST/API from internal" },
    { proto = "tcp", dport = tostring(local.svc_ports.elastic_transport), source = local.internal_src, comment = "Elasticsearch inter-node transport from internal" },
    { proto = "tcp", dport = tostring(local.svc_ports.kibana_web), source = local.internal_src, comment = "Kibana UI from internal" },
  ]
}

resource "proxmox_virtual_environment_cluster_firewall_security_group" "elastic_services" {
  name    = "elastic-svc"
  comment = "Elasticsearch REST (${local.svc_ports.elastic_http}) + transport (${local.svc_ports.elastic_transport}) + Kibana (${local.svc_ports.kibana_web}) from internal networks"

  dynamic "rule" {
    for_each = local.elastic_services_rules
    content {
      type    = "in"
      action  = "ACCEPT"
      proto   = rule.value.proto
      dport   = rule.value.dport
      source  = rule.value.source
      comment = rule.value.comment
    }
  }
}

resource "proxmox_virtual_environment_firewall_options" "elastic_container" {
  for_each = var.elastic_container_ids

  # Placement-aware: each cluster peer is firewalled on the node it lives on.
  node_name     = each.value.node_name
  container_id  = each.value.vm_id
  enabled       = local.firewall_defaults.enabled
  input_policy  = local.firewall_defaults.input_policy
  output_policy = local.firewall_defaults.output_policy
  log_level_in  = local.firewall_defaults.log_level_in
  log_level_out = local.firewall_defaults.log_level_out

  # DHCP-first guest (deployment.json dhcp=true) behind DROP in/out. Without
  # the firewall's dhcp allow, its own DHCPDISCOVER/OFFER is dropped and it
  # never leases an IP. Same treatment as the grafana/homepage containers.
  dhcp = true

  depends_on = [proxmox_virtual_environment_cluster_firewall.main]
}

resource "proxmox_virtual_environment_firewall_rules" "elastic_container" {
  for_each = var.elastic_container_ids

  node_name    = each.value.node_name
  container_id = each.value.vm_id

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.internal_access.name
    comment        = "Internal access (SSH, ICMP)"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.elastic_services.name
    comment        = "Elasticsearch REST + transport + Kibana (TCP/${local.svc_ports.elastic_http}, TCP/${local.svc_ports.elastic_transport}, TCP/${local.svc_ports.kibana_web})"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.outbound_internal.name
    comment        = "Outbound to internal (cluster peer discovery, DNS)"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.outbound_https.name
    comment        = "Outbound HTTPS (docker.elastic.co image pulls at converge)"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.outbound_http.name
    comment        = "Outbound HTTP (apt via the internal proxy, OCSP/CRL during TLS handshake)"
  }

  depends_on = [proxmox_virtual_environment_firewall_options.elastic_container]
}
