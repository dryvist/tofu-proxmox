# OpenHands Web is published on host TCP port 443. Traefik terminates public
# TLS and forwards plain HTTP to this service on the same host port.
locals {
  openhands_ports = {
    openhands_web = 443
  }
}
