# Ingress (Traefik HA) containers — the reverse-proxy instances behind the
# keepalived VRRP virtual IP (see ingress.tf `ingress_vip` / the keepalived role).
#
# DEFINE-DISABLED, exactly like the zero-trust rules: options.enabled is driven
# by local.ingress_fw_enabled (false today), so this whole firewall is inert and
# the ingress containers keep running un-firewalled — which is why keepalived
# VRRP already flows between them with no change. The value of declaring it now
# is that the eventual DROP-policy flip (its own observed PR) already PRE-ALLOWS
# VRRP + 80/443, so turning enforcement on can never black-hole the floating VIP
# or the HTTPS entrypoint. Mirrors the openbao/pipeline per-domain rule files.
#
# ponytail: 80/443 are the universal reverse-proxy entrypoints — inlined rather
# than promoted to pipeline_constants; add a constant only if a second consumer
# needs them.

resource "proxmox_virtual_environment_firewall_options" "ingress_container" {
  for_each = var.ingress_container_ids

  node_name    = var.node_name
  container_id = each.value
  # DEFINE-DISABLED: inert until local.ingress_fw_enabled flips to true.
  enabled       = local.ingress_fw_enabled
  input_policy  = local.firewall_defaults.input_policy
  output_policy = local.firewall_defaults.output_policy
  log_level_in  = local.firewall_defaults.log_level_in
  log_level_out = local.firewall_defaults.log_level_out

  depends_on = [proxmox_virtual_environment_cluster_firewall.main]
}

resource "proxmox_virtual_environment_firewall_rules" "ingress_container" {
  for_each = var.ingress_container_ids

  node_name    = var.node_name
  container_id = each.value

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.internal_access.name
    comment        = "Internal access (SSH, ICMP)"
  }

  # HTTPS + HTTP reverse-proxy entrypoints from internal (Traefik terminates TLS
  # and redirects :80 -> :443).
  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = "443"
    source  = local.internal_src
    comment = "Ingress HTTPS (Traefik) from internal"
  }

  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = "80"
    source  = local.internal_src
    comment = "Ingress HTTP->HTTPS redirect (Traefik) from internal"
  }

  # keepalived VRRP (IP protocol 112) between the ingress instances. Unicast VRRP
  # rides between the peer host IPs (all within internal_src); allowing it here is
  # the whole reason this define-disabled firewall exists — a future enforcement
  # flip must not drop the master-election traffic that owns the VIP.
  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "vrrp"
    source  = local.internal_src
    comment = "keepalived VRRP (proto 112) between ingress instances"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.outbound_internal.name
    comment        = "Outbound to internal only"
  }

  # Traefik fetches + renews its ACME cert via the Route53 DNS-01 solver, so it
  # needs outbound HTTPS to the ACME CA + AWS Route53 API (CDN-fronted, no stable
  # dest CIDR — reuses the same open-443 group as the Cribl license telemetry).
  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.outbound_https.name
    comment        = "Outbound HTTPS (ACME DNS-01: Let's Encrypt + Route53 API)"
  }

  depends_on = [proxmox_virtual_environment_firewall_options.ingress_container]
}
