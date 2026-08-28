# Ingress backend pools + assembled route list — split from ingress.tf so the
# route TABLE (ingress.tf) stays under the shared _file-size workflow's 12 KB
# error threshold (same locals-split treatment as locals-ingress-ha.tf).
# Locals merge across files in the module.
locals {
  # Ingress HA (keepalived VRRP VIP) locals — ingress_vip / ingress_hosts /
  # ingress_container_keys — live in locals-ingress-ha.tf so this file stays under
  # the shared _file-size workflow's 12 KB error threshold (locals merge across
  # files in the module, same split as locals-honeypot.tf / locals-vm-network.tf).

  # Proxmox cluster UI apex backend pool. Load-balanced across commissioned
  # nodes by role FQDN. Traefik skips backend cert verification.
  proxmox_ui_backends = [
    for name, n in var.nodes : "${n.role}.${var.domain}"
    if n.commissioned
  ]

  # Assembled routes: one {name, ip, port} per fronted service whose backend
  # container is actually defined (others are skipped, so a partial deployment
  # never emits a dangling route). The backend address comes from
  # local.container_address: a static guest's cidrhost IP, or a DNS-first
  # (dhcp = true) guest's FQDN — same hostname-not-IP shape as proxmox_ui_backends.
  # The Splunk VM is appended separately: it is a VM (not in var.containers), so
  # its IP comes from splunk_derived_ip (siem VLAN) rather than container_address.
  ingress_pre = [for route in concat(
    [
      for name, svc in local.ingress_services : merge({
        name        = name
        hostname    = try(svc.hostname, name)
        path_prefix = try(svc.path_prefix, null)
        priority    = try(svc.priority, null)
        ip          = local.container_address[svc.backend]
        port        = svc.port
        # Serving guest. Published so desc and section derive from it.
        owner = svc.backend
        # Authelia forwardAuth gate flag, consumed by the ansible traefik role.
        # Defaults true (gated) unless the table row opts out (sso = false).
        sso = try(svc.sso, true)
        # Dashboard grouping — see locals-ingress-groups.tf. Inherited from the
        # backend container's VLAN so no second tag list is maintained.
        group = try(svc.group, try(var.containers[svc.backend].vlan, "other"))
        # A route may state its own desc — several routes on one guest cannot
        # all read as that guest's summary. Merged in only when set, so an
        # absent one still falls through to the summary default below.
      }, try(svc.desc, null) != null ? { desc = svc.desc } : {})
      if contains(keys(var.containers), svc.backend)
    ],
    [
      {
        name  = "splunk"
        owner = "splunk"
        ip    = split("/", local.splunk_derived_ip)[0]
        port  = local.pipeline_constants.service_ports.splunk_web
        # Splunk Web serves HTTPS with a self-signed cert, unlike the HTTP
        # container backends. Traefik must speak https to it and skip verify.
        # Consumers default scheme=http / insecure_tls=false when absent.
        scheme       = "https"
        insecure_tls = true
        sso          = true # browser UI — gated
      },
      {
        # Splunk management / REST API (splunkd, 8089) fronted at
        # splunk-mgmt.<domain>. Single label deliberately: the *.<domain>
        # wildcard cert covers splunk-mgmt.<domain> but NOT a nested
        # mgmt.splunk.<domain>. splunkd's mgmt port is HTTPS self-signed, so
        # same https + skip-verify backend as the web route above.
        name         = "splunk-mgmt"
        owner        = "splunk"
        ip           = split("/", local.splunk_derived_ip)[0]
        port         = local.pipeline_constants.service_ports.splunk_mgmt
        scheme       = "https"
        insecure_tls = true
        sso          = false # REST API clients (CLI, automation)
      },
      {
        # Splunk HEC (8088) fronted at splunk-hec.<domain> on the standard
        # TLS entrypoint. HEC senders (the Cribl edges) must use this name:
        # splunk.<domain> resolves to Traefik, which serves nothing on a raw
        # 8088, so a sender dialing <name>:8088 black-holes. Same HTTPS
        # self-signed backend treatment as the other Splunk routes above.
        name         = "splunk-hec"
        owner        = "splunk"
        ip           = split("/", local.splunk_derived_ip)[0]
        port         = local.pipeline_constants.service_ports.splunk_hec
        scheme       = "https"
        insecure_tls = true
        sso          = false # HEC token senders (Cribl edges)
      }
    ],
    # Proxmox cluster UI apex (the ingress subdomain apex), load-balanced.
    # apex=true -> the Traefik Host rule is the base domain itself (no <name>.
    # prefix). backends (plural) -> a multi-server loadBalancer; sticky + health
    # checks give a stable per-browser session + drop a down node from the pool.
    # Omitted entirely if no node is commissioned (empty pool -> no route).
    length(local.proxmox_ui_backends) > 0 ? [
      {
        name         = "proxmox"
        apex         = true
        backends     = local.proxmox_ui_backends
        port         = local.pipeline_constants.service_ports.proxmox_web
        scheme       = "https"
        insecure_tls = true
        sticky       = true
        health_check = true
        sso          = false # tofu provider / API clients share this route
      }
    ] : [],
    local.ingress_lb_routes,
    # IaC automation platform routes (Terrakube + Semaphore on the iac-platform
    # VM) — assembled in locals-ingress-iac.tf to keep this file under the shared
    # _file-size 12 KB gate.
    local.iac_platform_routes
    # hostname defaults to the route name; group for a backend-less route comes
    # from the map in locals-ingress-groups.tf. Route-supplied keys win over both.
    ) : merge({
      hostname = route.name
      group    = try(local.ingress_route_groups[route.name], "other")
      owner    = null
      # ui follows sso: machine clients cannot do a browser login either way.
      # Exceptions in locals-ingress-audience.tf. desc comes from the guest.
      ui = contains(local.ingress_human_unauthed_routes, route.name) ? true : try(route.sso, true)
      # coalesce, not a try chain: an unset optional attribute is null, which
      # try returns rather than falling through. coalesce rejects "" as an
      # argument, so the outer try supplies the empty default.
      desc = try(coalesce(
        try(var.containers[route.owner].summary, null),
        try(local.ingress_pool_descriptions[route.name], null),
      ), "")
  }, route)]

  # Routes per guest — from the assembled list, so pools/VMs count too.
  ingress_owner_route_count = {
    for owner, routes in {
      for r in local.ingress_pre : r.owner => r... if r.owner != null
    } : owner => length(routes)
  }

  # A guest serving 2+ routes is a section. Derived, so nothing declares it.
  ingress = [
    for r in local.ingress_pre : merge(r, {
      section = try(local.ingress_owner_route_count[r.owner], 0) > 1 ? r.owner : null
    })
  ]
}
