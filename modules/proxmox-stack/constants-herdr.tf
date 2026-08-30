# herdr ports, split out of constants.tf for the shared 12 KB file-size gate —
# the same reason constants-dashboards.tf, constants-syslog.tf and
# constants-serving.tf exist. Locals merge, so downstream still sees one flat
# service_ports map.
#
# herdr is the agent multiplexer that owns the terminals the coding agents run
# in (nix-ai's nixosModules.herdr). Only ONE of its three guests is fronted:
#
#   herdr_relay_ws — herdr-remote's relay and web dashboard. Upstream binds
#     127.0.0.1:8375. WebSocket, so it needs Traefik's default HTTP/1.1
#     Upgrade handling and nothing more.
#
# The herdr runtime is reached over SSH and the Slack bridge speaks outbound
# Socket Mode, so neither takes a port here or a route in ingress.tf.
locals {
  herdr_ports = {
    herdr_relay_ws = 8375
  }
}
