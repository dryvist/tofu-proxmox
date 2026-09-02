# Review checklist — tofu-proxmox

Answer one verdict per entry against the diff only.

- id: no-targeted-apply
  Does the change introduce, document, or script a targeted (`-target=...`) apply?
  A partial apply republishes an incomplete inventory over the full artifact.
- id: no-check-blocks
  Does the change add a `check` block for a load-bearing assertion? A failed check only
  warns, so guards must be pre/postconditions or variable `validation`.
- id: node-name-forcenew
  Does the change alter a guest's `node_name`? That attribute is ForceNew, so the plan
  would destroy and recreate a running guest.
- id: no-literal-endpoints
  Does the diff add a literal hostname, IP address, port mapping, or credential? Reach a
  service by FQDN, never by a literal address, and never commit a secret.
- id: declared-attributes
  Does the change consume a new `deployment.json` attribute without declaring it in the
  matching variable schema? Undeclared attributes are silently stripped.
- id: boot-key-correctness
  Does the change set the boot-on-start key for the right guest kind? VMs use `on_boot`
  and containers use `start_on_boot`; the wrong key is silently stripped and reads back
  clean.
- id: fmt
  Is every changed `.tf` file `tofu fmt` clean?
- id: sensitive-variables
  Are new variables documented with a description, validated where they can be, and
  marked `sensitive = true` when they carry a secret?
- id: commit-subject
  Is the pull request title a Conventional Commits subject?
- id: docs
  Does changed behaviour come with the documentation update it needs?
