---
name: deployment-json-source-of-truth
description: deployment.json is the private RustFS desired-state object and terraform.tfvars must never exist
type: feedback
---

# deployment.json is the Single Source of Truth

The live `deployment.json` is a private, versioned RustFS object read by the
`tofu-proxmox` Terrakube workspace. It contains desired state, topology,
domain, and the public SSH key. It must never contain credentials or private
keys; those live in native OpenBao paths.

- Validate changes against `deployment.schema.json` before updating RustFS.
- Never commit the live object or create `terraform.tfvars`.
- Never bypass Terrakube workspace locking.
- Container and VM keys must match state addresses exactly; verify with a
  Terrakube state operation before renaming.
- A missing, empty, or structurally incomplete object must fail before plan.

## How to change it

Anything that adds a guest or changes `node_storage` is a write to this object,
because `main.tf` reads those values from it. You cannot make the change in a
`.tf` file, and there is no direct-write path around the lock.

The write goes through `flow-lock`, which holds a single-writer lease for the
duration of the update:

```bash
flow-lock run --ttl 15m --creds rustfs -- deployment-json edit --schema deployment.schema.json
```

`deployment-json` also takes `fetch [FILE]` and `put FILE --schema S`.

Four things trip up every first attempt:

1. **The binaries are not on `PATH`.** They ship inside the shared
   `inventory_resolve` role, which the Ansible consumer repos install from
   `dryvist/homelab-contracts`. Look for them under that role's `bin/`.
   Concluding the tooling is missing because `which flow-lock` fails is the
   easy mistake.
2. **`--creds rustfs` does not inject `DEPLOYMENT_JSON_S3_URI`.** It supplies
   the object-store endpoint, key, and secret. Without the URI set separately,
   `deployment-json fetch` fails with `missing DEPLOYMENT_JSON_S3_URI`. The
   object is the `deployment.json` key in the `iac-inventory` bucket, so the
   value is derivable — but something has to set it.
3. **Mint the AppRole `secret_id` with a generous `num_uses`.** flow-lock
   spends uses on lease acquire *and* release. Too few, and the release fails
   after the work succeeds, leaving the lease held by a dead process and
   blocking every other writer. Check `flow-lock status` before assuming the
   lock is free; recover a stranded lease with
   `flow-lock release --lease-id <id>`, reading the id from the lock object.
4. **A converge is not a writer.** Ansible reads the *published inventory*, not
   this object. Never wrap `ansible-playbook` in `flow-lock run` — it takes the
   global lease for the whole run and blocks real writers for no reason.
