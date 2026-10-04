# ZCode Web is published on host TCP port 443. Traefik terminates public TLS
# and forwards plain HTTP to this service on the same host port.
locals {
  zcode_ports = {
    zcode_web = 443
  }
}
