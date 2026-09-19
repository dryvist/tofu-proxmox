# Guest Naming Law

How every container and VM in this estate is named, and the plan-time guard that
enforces it. The VMID and address schemes live in
[INFRASTRUCTURE_NUMBERING.md](./INFRASTRUCTURE_NUMBERING.md).

**Enforced at plan time** by `modules/proxmox-stack/checks-guest-naming.tf`.
This page is the convention; the guard is the copy that runs.

A guest name is **`<app>-<suffix>`**, where `<app>` is the bare application
name — `technitium`, not `technitium-dns`; the protocol is redundant when the
application *is* the protocol. Qualify only when two genuinely distinct hosts
must be told apart.

`<suffix>` is a 1-4 digit number, in either of two accepted forms:

| Form | Shape | Example |
| --- | --- | --- |
| Legacy | `<node-digit><2-digit-instance>` — the node's logical digit, then a zero-based counter for that app on that node | `zammad-20`, `zammad-30` |
| Placement-neutral ordinal | Any 1-4 digit number that names nothing about the node | `llm-router-1`, `postgres-ai-2` |

Both forms are accepted for a pinned guest. The estate is converging on the
placement-neutral ordinal long term, but the guard does not force a rename —
see "Renaming an existing guest is a separate, riskier operation" below.

## The condition: only pinned guests carry a node digit

This is the half that gets forgotten, and forgetting it is how two guests in
this estate ended up carrying a digit for a node they were evacuated away from
years ago. Their names have been lying ever since.

A name that encodes a node is only ever true for a guest that **stays** on that
node — and even a pinned guest can be moved by an operator for a reason the
guard cannot see, which is why the guard no longer checks a pinned guest's
digit against its node's `logical_id`. Only one fact is still enforced:

- **Pinned** — the application supplies its own cross-node redundancy (quorum
  members, resolver secondaries, load-balanced ingress pairs). Losing the node
  loses one member, not the service, so the guest never moves. **These carry
  either accepted suffix form.**
- **Relocatable** — a singleton whose availability comes from HA migration
  (`ha = true`; see `ha.tf`). The scheduler may move it at any moment, so any
  numeric suffix would be false the instant it did. **These carry no numeric
  suffix at all.** The database, inventory, tracker, ticketing and media guests
  are all placement-neutral for this reason.

`ha = true` is the only machine-readable statement in the estate that a guest
moves for its availability, so it is what the guard reads.

## Two layers: logical digit vs corosync node id

The logical digit is **chosen**, declared once as `nodes.<node>.logical_id` in
the deployment object (`modules/proxmox-stack/variables-infrastructure.tf`), and
referenced from nowhere else.

It is **not** the corosync node id and must never be reconciled to it. Corosync
numbers nodes by join order — an accident of cluster history that changes when a
node is rebuilt and rejoins. The logical digit is picked to be stable and
memorable: normally the leading digit of the node's hardware model, and where
two models lead with the same digit, a free digit instead. The two numbering
layers currently disagree, and that divergence is deliberate.

The guard rejects two nodes claiming the same `logical_id`. A node that declares
no `logical_id` opts out: its guests are not judged, the same way a node absent
from `node_storage` is not judged by the datastore guard.

## What the guard rejects

| Condition | Why |
| --- | --- |
| A numeric suffix longer than 4 digits | Neither accepted form is that long. |
| A numeric suffix on a guest with `ha = true` | A relocatable guest cannot truthfully encode a node. |
| Two nodes with the same `logical_id` | Every name built from that digit is ambiguous. |

Pre-law names awaiting a planned rename are listed in the private desired
state's `guest_naming_exceptions` (guest name -> reason), wired into
`var.guest_naming_exceptions` in `checks-guest-naming.tf` via `main.tf` — not
committed here, since the roster is real guest names and this repository is
public. Shrink that list; never grow it, and never weaken the rule to make a
name pass.

> **Renaming an existing guest is a separate, riskier operation.** A guest that
> derives its cluster identity from its hostname rejoins as a **new** peer under
> a new name, while the old entry lingers as a failed voter. Renames ride a
> planned resize, verified against this guard — the guard lands first.
