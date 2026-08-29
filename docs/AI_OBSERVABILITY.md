# AI usage observability

How AI coding-agent telemetry (tokens, cost, cache economics, context size)
becomes dashboards. This page is the repo-scoped contract; operational values
live in the private configuration.

## The guest

One observability container (`grafana` tag, declared in the desired state)
runs Grafana OSS and VictoriaMetrics single-node as a compose stack,
configured by the `grafana_stack` role in the config-management repo.

| Service | Port constant | Role |
| --- | --- | --- |
| Grafana | `service_ports.grafana_web` | Dashboards, Traefik-fronted, SSO-gated |
| VictoriaMetrics | `service_ports.victoriametrics` | Long-retention TSDB; Prometheus `remote_write` receiver and Grafana datasource |

Both ports are open from internal networks only (`modules/firewall/
grafana_rules.tf`). The UI is reached through the ingress `grafana` route.

## Data flow (what, not where)

1. Coding agents export OpenTelemetry (metrics + logs) to the estate's
   existing OTLP ingest (`modules/firewall/otlp_ingest_rules.tf`).
2. The stream pipeline routes metrics onward as Prometheus `remote_write`
   into VictoriaMetrics, and usage events into the log platform.
3. A per-workstation ETL summarizes agent session logs (cache TTL split,
   context-size trends) and pushes derived series the same way.
4. Grafana dashboards are provisioned by the role — the UI carries no
   hand-built state and rebuilds clean.

## Dashboards

Provisioned set: usage overview (tokens/cost by model), cache economics
(read/write ratio, TTL split), context bloat, subagents and tools,
subscription burn. Dashboard JSON lives with the role, not here.

## Invariants

- Ports are referenced only through `service_ports` constants — never
  literals outside `modules/proxmox-stack/constants.tf`.
- The guest is DNS-first (`dhcp: true`); nothing references a literal
  address.
- VictoriaMetrics is internal-only; nothing exposes it through ingress.
