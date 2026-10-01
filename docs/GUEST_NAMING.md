# Guest Naming

Every guest name is policy-generated as `<app>-<VMID>`, never hand-picked and
never an ordinal (`-1`/`-2`/`-3`). `<app>` is the desired-state key with any
trailing `-<digits>` stripped.

That generator is **not yet live** in this repo. A prior attempt
(`local.guest_hostname_containers` / `guest_hostname_vms`) was reverted —
"keep declared guest names until the rename wave" (PR #1143, 2026-09-20) —
because live guests still carry hand-declared `hostname`/`name` values, and a
blind switchover would have renamed them out from under DNS and inventory.
Until the rename wave runs, `hostname` in the private desired state is read
as-authored, not derived. New desired-state entries should still be
hand-authored as `<app>-<VMID>` to avoid a second rename later.

Some per-node ("DaemonSet-style") service templates
(`locals-node-services.tf`) and the OpenBao cluster peers (`main.tf`) still
emit a two-digit ordinal `<prefix><NN>` suffix instead of `<app>-<VMID>`.
That is a known deviation from the naming policy, not the intended form for
new work.
