terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.70.0"
    }
  }
}

# NOTE: AWS Provider is configured in parent module (aws-infra/main.tf)
# This module inherits the provider from its parent

# A Record for Proxmox VE UI
# Points the Proxmox domain to all active Proxmox API endpoints.
# Gated OFF by default: the Proxmox endpoints are RFC1918 hosts, so publishing
# them in the PUBLIC hosted zone leaks internal IPs. Internal clients resolve
# pve.<domain> via Technitium (authoritative for the pve subdomain zone), so the
# public record is unnecessary. Flip publish_proxmox_public_a=true only if an
# off-LAN consumer genuinely needs it. Cert renewal is unaffected — lego DNS-01
# writes only _acme-challenge.* TXT, never this A record.
resource "aws_route53_record" "proxmox" {
  count = var.publish_proxmox_public_a ? 1 : 0
  #checkov:skip=CKV2_AWS_23: Proxmox is on-premises infrastructure with a static IP; AWS alias resource is architecturally inapplicable
  zone_id = var.route53_zone_id
  name    = var.proxmox_domain
  type    = "A"
  ttl     = var.dns_ttl
  records = local.proxmox_ip_addresses

  lifecycle {
    # Prevent accidental deletion of critical DNS record
    prevent_destroy = false # Set to true in production
  }
}

# Service-alias CNAMEs at the zone apex (e.g. a capability name pointing at
# the host that serves it). Labels are relative to the hosted zone; values
# arrive via ROUTE53_CNAMES (tofu env input), never as committed
# literals. ACME DNS-01 clients that locate the hosted zone by stripping one
# label need these aliases placed directly under the public zone.
resource "aws_route53_record" "service_cnames" {
  for_each = var.route53_cnames

  zone_id = var.route53_zone_id
  name    = each.key
  type    = "CNAME"
  ttl     = var.dns_ttl
  records = [each.value]
}

# Host A records at the zone apex (e.g. a Mac's own FQDN pointing at its LAN
# IP). Labels are relative to the hosted zone; values arrive via
# ROUTE53_A_RECORDS (tofu env input), never as committed literals. A
# CNAME chain that terminates at one of these names (see service_cnames
# above) only resolves once the terminal name itself has an A record here —
# Technitium (the internal resolver) is authoritative for the guest subdomain
# only and forwards apex names like these to public resolvers, so this zone is
# the single source of truth both internal and external queries land on.
resource "aws_route53_record" "service_a_records" {
  #checkov:skip=CKV2_AWS_23: Targets are on-premises/LAN hosts with static IPs; AWS alias resource is architecturally inapplicable
  for_each = var.route53_a_records

  zone_id = var.route53_zone_id
  name    = each.key
  type    = "A"
  ttl     = var.dns_ttl
  records = [each.value]
}
