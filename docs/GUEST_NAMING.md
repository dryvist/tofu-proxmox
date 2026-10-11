# Guest Naming

A new `containers`/`vms` entry gets its hostname/name GENERATED, never
declared: `<app>-<vm_id>`, where `<app>` is the desired-state map key with
any trailing `-<digits>` stripped (e.g. key `llm-router-1` -> app
`llm-router`). This is one shared local
(`local.guest_hostname_containers` / `local.guest_hostname_vms` in
`modules/proxmox-stack/locals-guest-naming.tf`).

**A guest that already declares `hostname`/`name` in the desired state keeps
that value, verbatim, until its own rename wave.** There is no exception
list and no guard: the rule is a property of the desired-state object
itself — declared beats generated. A new guest simply omits the field (both
fields are `optional(string)`) and gets the generated form; an existing
guest keeps whatever it already declares. Deleting a guest's declared
`hostname`/`name` — one guest at a time, as its own rename wave lands — is
what moves it onto the generated name; nothing here does that automatically.

The VMID digits carry the meaning: see the VMID scheme in the private
documentation.

## Generator paths are NOT covered by this rule

The OpenBao cluster generator (root `main.tf`,
`openbao_generated_containers`) builds each peer's map key and hostname from
its placement item:

- An integer item keeps the ordinal `"<prefix><NN>"` formatting (e.g.
  `openbao-01`).
- An object item `{"vm_id": N}` uses `<app>-<vm_id>` (e.g. `openbao-110050`).
  An explicit `"hostname"` on the item replaces that name.

The per-node service generator (root `locals-node-services.tf`,
`node_service_containers`) has no object form and still uses the ordinal
key.

This is deliberate, not an oversight. For a `containers`/`vms` entry, the
map key always comes from the desired state and is never touched by the
hostname rule above, so switching an entry between declared and generated
hostname never changes its Terraform resource address. The two generators
are different: they synthesize the WHOLE object, including the map key
itself, and that key IS the resource address
(`module.containers[0]...containers[<key>]`). A live credentialed plan
against the workspace proved that regenerating that key as `<app>-<vm_id>`
plans a destroy-and-recreate of every live guest the generator already
produced (OpenBao Raft voters `openbao-01`, `-02`, `-10`, `-20`, `-21`,
`-31`, `-42` and the `traefik-*` per-node instances, as of this writing) — an
integer placement item has no hostname field to opt an existing peer out,
the way a `containers`/`vms` entry can.

An object placement item does have one: its optional `"hostname"` names an
existing peer's live key, so that peer keeps it. The per-node service
generator has no such field and keeps `format("%s%02d", prefix, suffix)`.
