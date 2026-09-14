# Elastic Stack

Full-text search + analytics over estate logs **and** a shared search backend
for self-hosted apps — explicitly **not** a SIEM replacement. Splunk remains the
system of record for security monitoring; Elastic is the search plane next to
it. This page is the repo-scoped contract; operational values (node keys,
VMIDs, `logical_id`s, VLAN IDs, storage) live in the private desired state and
are never written here.

## The cluster

Two `elastic`-tagged LXC containers (declared in the desired state) each run
Elasticsearch **and** Kibana as one Docker-in-LXC compose stack, configured by
the `elastic_stack` role in the config-management repo.

| Service | Port constant | Role |
| --- | --- | --- |
| Elasticsearch REST | `service_ports.elastic_http` | API + ingest (Cribl writes here); internal-only |
| Elasticsearch transport | `service_ports.elastic_transport` | Node-to-node (discovery, replication) — cluster peers only |
| Kibana | `service_ports.kibana_web` | UI, Traefik-fronted, SSO-gated |

Both guests are placed on the **two always-on hosts** as keyed in
`deployment.json` (the primary and its always-on peer). Placement is a
standard, not a choice — the pair is what lets the cluster live hot/hot. Names
follow the naming law (`elastic-<node-digit><instance>`), derived from each
node's `logical_id`, and are **never** restated with a node mapping in this
public repository.

### Hot / hot — and the quorum reality

Both peers are data + master-eligible with `number_of_replicas: 1` — hot/hot,
no standby. This is **not** high availability: with two master-eligible nodes,
2 of 2 votes are required to elect a master, so losing either node stops writes
(and master-dependent APIs) until it returns. Index data survives the loss via
replicas; the service does not. That is the documented price of a two-node
pair, and it is why the operations posture (below) spells out recovery — it is
not "start the survivor."

## Security

- `xpack.security` is **enabled** (ES 8+ default; crypto on by default).
- Transport **and** HTTP TLS, both from one cluster CA issued by **OpenBao PKI**
  — the CA keypair is generated inside OpenBao and never exported. Each node's
  certificate carries SANs for its node name and FQDN. A role-local
  `certutil` CA (one per guest) is explicitly rejected: it would create two
  unrelated CAs and the cluster could never form.
- Kibana uses per-cluster service credentials (never the `elastic` superuser);
  the Cribl ES output uses a least-privilege ingest principal.
- The ES REST API (9200) is **not** fronted by Traefik. Kibana (5601) is.

## Firewall

`modules/firewall/elastic_rules.tf` is the estate's first **placement-aware**
rule set. The cluster spans two nodes and the default-deny guest firewall is a
per-node resource, so `elastic_container_ids` is a
`map(object({ vm_id, node_name }))` carrying each guest's placement, and every
elastic resource uses `each.value.node_name` / `each.value.vm_id`. This is what
lets the second peer (on the other host) be firewalled at all — every other
rule file keys off the single module-level `node_name`.

## Ingress

One `kibana.<domain>` route load-balances **both** peers' Kibana UIs, health-
checked on `/api/status` (a peer whose colocated ES is down gets evicted).
Each Kibana points at **both** ES hosts and shares the xpack encryption keys,
so either survivor serves the full UI. The route is tag-derived (`elastic`),
auto-filed on all three dashboards, and SSO-gated.

## Data flow into Elastic

Logs reach Elastic from the existing pipeline: Cribl Stream gains an `elastic`
output (basic auth, dedicated least-privilege ingest role) with a
normalization/redaction pipeline and a bounded index expression. The guests'
**own** app logs ride the ai_log pipeline to the `elastic` Splunk index
(`constants-ai-log.tf` `elastic_docker`), exactly like clickhouse/phoenix.

## Invariants

- Ports are referenced only through `service_ports` / `ai_log_ports` constants —
  never literals outside `modules/proxmox-stack/constants-*.tf`.
- Both guests are DNS-first (`dhcp: true`); nothing references a literal
  address.
- Node identity is never a literal in this repo — it comes from
  `deployment.json` (placement, `logical_id`s) and the published inventory.
- The REST API stays internal-only; nothing exposes it through ingress.

## Operations posture

- **`vm.max_map_count` = 1048576** (ES ≥ 8.16 requirement) on both hosts,
  owned by the host-config repo's sysctl role, applied before guest converge,
  verified after reboot. Host-global — no LXC-side setting exists.
- **Recovery procedures** must exist before a node is deliberately lost:
  planned node removal, permanent-node-loss (vote quorum detach), and
  full-cluster restart. ILM/rollover/retention and disk-watermark alerting are
  provisioned before the Cribl Stream fan-out is enabled.
- Bootstrap is a coordinated state machine (shared certs → both nodes start →
  one cluster UUID → service users set in ES → `initial_master_nodes` removed →
  sequential restart) — never an ordinary per-host role run.

## Related

- [AI_OBSERVABILITY.md](./AI_OBSERVABILITY.md) — the Grafana/VictoriaMetrics
  observability guest, the sibling pattern this follows.
- [SPLUNK_INDEXES.md](./SPLUNK_INDEXES.md) — Splunk stays the SIEM system of record.
