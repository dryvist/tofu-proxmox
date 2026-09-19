# Guest Naming

Every container/VM name is GENERATED, never declared: `<app>-<vm_id>`,
where `<app>` is the desired-state map key with any trailing `-<digits>`
stripped (e.g. key `llm-router-1` → app `llm-router`). Nothing is
hand-named — `hostname`/`name` in the private desired state, if still
present, is ignored (`modules/proxmox-stack/locals.tf`,
`local.guest_hostname_containers` / `local.guest_hostname_vms`).

The VMID digits carry the meaning: see the VMID scheme in the private
documentation. Supersedes the earlier node-digit naming law.
