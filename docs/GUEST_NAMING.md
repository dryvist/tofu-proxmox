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
`openbao_generated_containers`) and the per-node service generator (root
`locals-node-services.tf`, `node_service_containers`) still build the map
key with the ordinal `"<prefix><NN>"` formatting (e.g. `openbao-01`), not
`<app>-<vm_id>`.

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
`-31`, `-42` and the `traefik-*` per-node instances, as of this writing) —
there is no per-peer "declared hostname" field in the private placement
data to opt an existing peer out, the way a `containers`/`vms` entry can.

Closing this gap needs a schema change to the private `openbao_cluster`
and `node_services` placement data (an optional per-peer hostname override,
so an existing peer can declare its live key the same way a regular guest
declares `hostname`) before the ordinal formatting can be removed from
these two paths. Until then they keep `format("%s%02d", prefix, suffix)`.

## History

An earlier version of this rule generated every hostname unconditionally,
ignoring any declared value (see this repo's git history for the PRs that
introduced and then reverted it). That renamed every existing guest in the
same apply, which is the rename wave this rule is designed to avoid. The
declared-beats-generated rule above is what replaced it, for the
`containers`/`vms` paths where it is safe.
