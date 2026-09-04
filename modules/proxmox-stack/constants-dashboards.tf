# Dashboard and co-located-agent-UI ports.
#
# Split into its own file (merged into pipeline_constants.service_ports by
# constants.tf) so that file stays under the shared _file-size 12 KB error
# threshold — the same reason ai_log_ports and the serving constants live
# beside it. Locals merge across files in the module, so downstream consumers
# still see one flat service_ports map and nothing about the split is visible
# in the published inventory.

locals {
  dashboard_ports = {
    # Estate dashboards alongside homarr_web (7575, in constants.tf). All three
    # boards are populated from the SAME published ingress list
    # (locals-ingress-backends.tf), so a service reaches every board by having a
    # Traefik route — never by being added to a per-board list. Each runs in its
    # own guest, so the upstream defaults never collide.
    homepage_web = 3000
    glance_web   = 8080

    # Status guest (Docker-in-LXC): Gatus catalog synthetics + Uptime Kuma
    # keystone status page. Distinct host ports so Traefik can route each;
    # both backends share the `status` container hostname.
    gatus_web       = 8080
    uptime_kuma_web = 3001

    # The two most popular third-party Hermes UIs. Both load the agent LOCALLY —
    # hermes-webui in-process from HERMES_HOME, hermes-studio over a unix socket
    # / loopback bridge — so neither can be split into a guest of its own the way
    # hermes-ui's remote-capable workspace can. They run ON each hermes-agent
    # guest, which is why these ports are opened by that guest's security group
    # (modules/firewall/hermes_agent_rules.tf) rather than hermes-ui's.
    hermes_webui  = 8787
    hermes_studio = 8648

    # hermes-ui — the companion guest running two DIFFERENT apps that both
    # default to 3000 upstream (hermes-workspace, the remote-capable Hermes web
    # workspace, and mission-control, an unrelated co-located product), mapped
    # to distinct host ports so Traefik can route each independently.
    hermes_ui_workspace       = 3000
    hermes_ui_mission_control = 3001
  }
}
