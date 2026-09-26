# Guest Naming

A new guest's hostname/name is GENERATED, never declared: `<app>-<vm_id>`,
where `<app>` is the desired-state map key with any trailing `-<digits>`
stripped (e.g. key `llm-router-1` -> app `llm-router`). This applies to every
guest path — a regular `containers`/`vms` entry, an OpenBao Raft peer, and a
per-node ("DaemonSet-style") service instance — through one shared local
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

## Generator paths

The OpenBao cluster generator (root `main.tf`) and the per-node service
generator (root `locals-node-services.tf`) both key their generated
container map on `<app>-<vm_id>` directly and set no `hostname` of their
own — the shared local above then generates the same string from that key,
a no-op round-trip. Earlier revisions built the hostname with an ordinal
suffix (`format("%s%02d", prefix, suffix)`, e.g. `openbao-01`); that
formatting is gone from both paths in favor of the one base formatter.

## History

An earlier version of this rule generated every hostname unconditionally,
ignoring any declared value (see this repo's git history for the PRs that
introduced and then reverted it). That renamed every existing guest in the
same apply, which is the rename wave this rule is designed to avoid. The
declared-beats-generated rule above is what replaced it.
