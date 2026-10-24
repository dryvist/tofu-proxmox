# Web UIs fronted by Traefik that have no other constant home.
#
# Split out of constants.tf (merged into pipeline_constants.service_ports
# there) so that file stays under the shared _file-size 12 KB error threshold.
# The ingress table in ingress.tf references these through service_ports,
# never by literal port.

locals {
  web_ui_ports = {
    technitium_web    = 5380
    authelia_portal   = 9091
    phpipam_web       = 80
    nautobot_web      = 8080
    vikunja_web       = 3456
    homebox_web       = 7745
    zammad_web        = 8080 # nginx in-guest, own container IP (independent of nautobot's 8080); Traefik-fronted
    homeassistant_web = 8123
    openproject_web   = 80
    prometheus_web    = 9090
  }
}
