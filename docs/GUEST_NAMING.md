# Guest Naming Law

Every container/VM name, enforced at plan time by
`modules/proxmox-stack/checks-guest-naming.tf` (VMID/address schemes:
[INFRASTRUCTURE_NUMBERING.md](./INFRASTRUCTURE_NUMBERING.md)).

**The rule:** a name is `<app>` or `<app>-<n>`. `<app>` is the bare
application name — `technitium`, not `technitium-dns` — never a hardware,
model, or node token (`llm-4080`, `docker-540` are illegal).

`<n>` is the instance ordinal: 1-2 digits, no leading zero, and per `<app>`
the ordinals in use are exactly `1..N` with no gaps or duplicates — a suffix
always means "instance n of N". Placement is never encoded, so a reboot, HA
move, or rebuild never touches a name.

A guest with no suffix is a single instance; a second instance renames the
first to `-1` (stateless guests are rebuilt, never renamed in place).

Pre-law names await a planned rename via the private desired state's
`guest_naming_exceptions` (name -> reason) — shrink it, never grow it.

Supersedes the legacy `<node-digit><instance>` form.
