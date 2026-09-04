# Dashboards and agent UIs

Every browser surface in this estate is reached at
`https://<name>.$PVE_SUBDOMAIN` — a clean single-label hostname, no port, always
through Traefik and its Authelia gate. Nothing here should ever require
remembering a port number.

This document covers the two families of browser surface that are easy to get
wrong: the estate dashboards, and the several web UIs that front a Hermes agent.

## The route table is the single source

`modules/proxmox-stack/ingress.tf` (single routes) and
`locals-ingress-backends.tf` (load-balanced pools and VM-backed routes) assemble
`local.ingress`, which is published as `ansible_inventory.ingress`. That list is
the *only* enumeration of fronted services. Traefik, the DNS role, and all three
dashboards read it.

Practical consequence: **a service gets on every dashboard by having a Traefik
route**, never by being added to a dashboard's own list. There is no second list
to keep in sync, and there is no way for a board to drift out of date.

### Grouping

Each assembled route carries a `group`, used as the section heading on every
board. It is inherited from the backend container's `vlan`, because the VLAN is
already an accurate and already-maintained statement of what a guest is. Routes
with no backend container — load-balanced pools, the Splunk VM, the IaC platform
VM — have no VLAN to inherit and are listed explicitly in
`locals-ingress-groups.tf`.

So adding a guest to a VLAN files it on all three boards. Adding a *tag* for
grouping is unnecessary and would be a second thing to maintain.

The `ansible_inventory_ingress_route_table` contract test asserts both that every
row carries a non-empty group and that a container-backed row actually inherits
its backend's VLAN — the second assertion is what catches inheritance silently
collapsing while the first still passes.

## The three dashboards

| Board | Port constant | Config model |
| --- | --- | --- |
| Homarr | `homarr_web` | tRPC API |
| Homepage | `homepage_web` | YAML files |
| Glance | `glance_web` | YAML file with includes |

All three are declared with the shared `dashboard` tag alongside their own, so
the set is addressable as a whole.

## Health surfaces (where to look)

| Question | UI |
| --- | --- |
| Does the **user-facing URL** work (incl. Traefik 504 / Authelia `invalid_client`)? | **Gatus** (`gatus.$PVE_SUBDOMAIN`) — catalog probes every 60s with follow-redirects; OIDC `client_id` authorize probes |
| Are **keystones** up? | **Uptime Kuma** (`uptime-kuma.$PVE_SUBDOMAIN`) + **Healthchecks** + Gatus `keystone` group |
| Is the **guest process** answering? | Homepage / Glance status dots + Homarr `pingUrl` (catalog `probe_url`) |
| Network / WAN quality? | Grafana blackbox dashboards + Prometheus |
| Native app APIs (Sonarr / Plex / …)? | Homarr integrations |

Gatus and Uptime Kuma run on the shared **`status`** guest (Docker-in-LXC). A
service reaches Gatus by having a Traefik route (same catalog as the boards).

Two things worth knowing before touching their Ansible roles:

- **Homarr's API `create` always inserts.** Its role must list what exists and
  diff by name, or every converge duplicates the whole board. Homepage and Glance
  are file-rendered, so a byte-identical render is naturally a no-op.
- **Glance ships no authentication of its own.** The Authelia gate on its Traefik
  route is the only thing in front of it — that route must never opt out of SSO.

### Links out, and the one exception

Every link on every board points at `https://<name>.$PVE_SUBDOMAIN`, so each
click passes through Authelia. No board should ever contain a `host:port` URL.

The exception is *status checking*, not linking. Homepage's `siteMonitor` and
Glance's `monitor` issue an unauthenticated `HEAD`; pointed at a gated public URL
they report every service down. If status indicators are wanted, they must probe
the internal address (`container_address`, already published in the inventory).
No click ever routes through a probe. If that trade is unwanted, omit the status
widgets rather than opening the gate.

## Hermes agents: which UI is which

Hermes agents are declared with the `hermes-agent` tag. Every tagged guest gets a
complete route set generated in `locals-hermes-routes.tf` — dashboard, webhook
receiver, job API, and the two co-located third-party UIs — so **adding an agent
needs no ingress edit**.

| Surface | Reached at | Scope |
| --- | --- | --- |
| Open WebUI | `chat.$PVE_SUBDOMAIN` | **every agent, one login** |
| Hermes Dashboard | `<agent>.$PVE_SUBDOMAIN` | one agent |
| hermes-webui | `<agent>-webui.$PVE_SUBDOMAIN` | one agent |
| hermes-studio | `<agent>-studio.$PVE_SUBDOMAIN` | one agent |
| hermes-workspace | `hermes-ui.$PVE_SUBDOMAIN` | one agent at a time |

**Open WebUI is the single pane.** Each agent exposes an OpenAI-compatible API,
and Open WebUI holds one connection per agent, listing each as its own selectable
model. It is the only surface here that shows every agent behind one login. The
inventory publishes `hermes_agents` — one entry per tagged guest, each `api_url`
ending `/v1` — so the consuming role wires up a new agent with no edit anywhere.

> The `/v1` suffix is part of the contract. Without it, Open WebUI's connection
> test still passes and then lists no models at all.

Every other surface is inherently per-agent. The built-in Dashboard is
machine-level with no fleet view; hermes-webui loads the agent in-process and
hermes-studio reaches it over a local socket, which is why those two run **on**
each agent guest rather than in guests of their own — they cannot be separated
from the agent they serve. hermes-workspace is the exception that talks HTTP and
so runs in its own guest, but it points at one agent at a time.

### Why hostnames must not be renamed

The Hermes Dashboard rebuilds its OIDC `redirect_uri` from its statically
configured `public_url`, not from the request `Host`. Renaming a published route
therefore sends the browser to a host that cannot complete the login. The first
agent's established hostnames are preserved by the override map in
`locals-hermes-routes.tf`; new agents default to their container key. Assertions
in `modules/proxmox-stack/tests/locals.tftest.hcl` cover both.

All generated hostnames are single labels, because the wildcard certificate
covers exactly one level below the ingress subdomain.

### Task tracking: two boards, deliberately separate

- **Vikunja** (`vikunja.$PVE_SUBDOMAIN`) is the estate task tracker, with full
  create/edit/delete in the browser.
- **Each Hermes agent additionally keeps its own internal board**, served as a
  `/kanban` tab on that agent's dashboard over the agent's own task store.

These are not synced, and that is intentional. An agent's internal board is its
working state; Vikunja is the estate's record. To see one agent's tasks, go to
that agent's dashboard.
