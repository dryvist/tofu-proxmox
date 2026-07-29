# Syslog source-family port/routing registry — split from constants.tf for
# the file-size gate; same locals namespace, exported through
# ansible_inventory.constants exactly as before.
locals {
  # Syslog source-family routing map — the single source of truth for the
  # syslog pipeline. standard = app-facing HAProxy frontend port; high =
  # backend port HAProxy forwards to (the Cribl Edge listener); index/
  # sourcetype = Splunk routing stamped by the Cribl Edge syslog pipeline.
  # Consumed by modules/firewall and exported through
  # ansible_inventory.constants for the HAProxy/Cribl roles, the
  # validate-pipeline playbook, and the pytest E2E fixtures in
  # ansible-proxmox-apps.
  syslog_port_map = {
    unifi     = { standard = 514, high = 1514, index = "unifi", sourcetype = "ubiquiti:unifi" }
    palo_alto = { standard = 515, high = 1515, index = "firewall", sourcetype = "pan:firewall" }
    cisco_asa = { standard = 516, high = 1516, index = "firewall", sourcetype = "cisco:asa" }
    linux     = { standard = 517, high = 1517, index = "os", sourcetype = "syslog" }
    windows   = { standard = 518, high = 1518, index = "os", sourcetype = "syslog" }
    # Honeypot deception events (OpenCanary tripwires per VLAN + T-Pot deep
    # sensor). standard 519 = the HAProxy frontend honeypots ship to; high 1519
    # = the Cribl Edge backend. Lands in the dedicated `honeypot` Splunk index
    # (Path B — forensics/correlation) in parallel with the real-time apprise
    # push (Path A). T-Pot reuses the same frontend with its sourcetype set by
    # the Cribl Edge pipeline. See docs/HONEYPOTS.md + docs/SPLUNK_INDEXES.md.
    honeypot = { standard = 519, high = 1519, index = "honeypot", sourcetype = "honeypot:opencanary" }
    # UniFi firewall/IPS/threat syslog, split from the admin/system stream above so
    # security events land in the dedicated `firewall` index instead of being buried
    # in `unifi`. standard 520 = HAProxy frontend; high 1520 = Cribl Edge backend.
    # Until the controller can target a second syslog destination, the split is done
    # Cribl-side by sourcetype routing on the shared 514 receiver; this family gives
    # the eventual dedicated receiver a stable, pre-allowed port.
    unifi_fw = { standard = 520, high = 1520, index = "firewall", sourcetype = "ubiquiti:firewall" }
    # macOS host syslog (MacBook + Mac Studio). Own family so Mac logs stop sharing
    # the UniFi backend port (1514) they currently point at; lands in `os` alongside
    # linux/windows, distinguished by sourcetype. standard 521 = HAProxy frontend;
    # high 1521 = Cribl Edge backend.
    macos = { standard = 521, high = 1521, index = "os", sourcetype = "syslog:macos" }
    # Technitium DNS query logs (per-VLAN resolvers). Dedicated family so DNS
    # visibility for threat-hunting lands in its own `dns` index. standard 522 =
    # HAProxy frontend; high 1522 = Cribl Edge backend.
    dns_query = { standard = 522, high = 1522, index = "dns", sourcetype = "technitium:dnsquery" }
    # L7 proxy access logs (Traefik ingress + HAProxy). Dedicated `proxy` index for
    # ingress/L7 visibility. standard 523 = HAProxy frontend; high 1523 = Cribl Edge
    # backend. Traefik and HAProxy are distinguished by sourcetype in the pipeline.
    proxy = { standard = 523, high = 1523, index = "proxy", sourcetype = "haproxy" }
    # Hypervisor health telemetry — one structured key=value line per node per
    # sample interval (stall detection, clocksource, replication, HA state,
    # memory pressure, guest drift). Emitted by the pve_health_telemetry role in
    # the host-config repo via the journal, so it needs no agent and no new
    # listener beyond this family.
    #
    # WHY its own family rather than riding the linux family: linux lands in the
    # `os` catch-all, and `os` is already the largest index by a wide margin
    # while carrying three unrelated OS families. Health telemetry is queried in
    # a completely different way from host syslog — it is a dense, regular
    # series that gets charted and alerted on, not read as event text — and
    # burying a 1-line-per-minute series inside a high-volume free-text index
    # makes both harder to use.
    #
    # Routing by listener (a dedicated port) rather than by payload inspection
    # is the same pattern every other family here uses, and it means this works
    # independently of the host-keyed `os` decomposition rather than waiting on
    # it. Lands in the existing os_proxmox index — hypervisor-scoped and already
    # declared — so this adds a route, not another index to manage.
    pve_health = { standard = 524, high = 1524, index = "os_proxmox", sourcetype = "pve:health" }
  }
}
