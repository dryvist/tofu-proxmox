# Honeypot / deception sensor ports. apprise_api = the honeypot-notify gateway's
# REST port (caronc/apprise-api): honeypots POST one webhook and Apprise fans
# it out to Slack + phone push (Path A). The remaining entries are the
# low-interaction decoy services the per-VLAN OpenCanary tripwires emulate —
# the firewall honeypot_services group ACCEPTs+logs these from internal so an
# intruder touching ANY of them trips an alert. SSH (22) is already covered by
# internal_access. The honeypot syslog frontend (519) lives in syslog_port_map
# in constants.tf. Consumed by modules/firewall and the opencanary/apprise/tpot
# roles in ansible-proxmox-apps. See docs/HONEYPOTS.md.
#
# Split into its own file (referenced from constants.tf as local.honeypot_ports)
# so constants.tf stays under the shared _file-size 12 KB error threshold;
# locals merge across files in the module.
locals {
  honeypot_ports = {
    apprise_api = 8000
    ftp         = 21
    telnet      = 23
    http        = 80
    https       = 443
    smb         = 445
    tftp        = 69   # udp
    snmp        = 161  # udp
    ntp         = 123  # udp — OpenCanary NTP module (honeypot CTs only; no host chrony clash)
    sip         = 5060 # udp
    mssql       = 1433
    mysql       = 3306
    postgres    = 5432
    rdp         = 3389
    vnc         = 5900
    redis       = 6379
    git         = 9418
    http_proxy  = 8080
  }
}
