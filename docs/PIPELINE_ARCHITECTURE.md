# Pipeline architecture (this repo's role)

> Split out of `AGENTS.md` (shared 12 KB file-size gate) — same authority,
> different file.

This repo is the **single source of truth** for infrastructure: VMs,
containers, IPs, ports, and firewall rules.

> **Standing policy — Nautobot is the system of record for infrastructure
> inventory.** Nautobot owns every fact it can model: device identity,
> hardware (serials, asset tags, models), interfaces and MAC addresses, IP
> addresses and their DNS names, rack and power topology, and location. No
> dynamic — or possibly-dynamic — configuration may live outside it. Every
> other system references Nautobot rather than keeping its own copy: OpenTofu
> reads from it at plan time, Ansible reads from it, and docs point at it
> instead of restating its contents.
>
> **Migration status — direction, not accomplished fact.** Nothing reads from
> Nautobot yet. This repo still derives every IP from `deployment.json` and
> publishes `ansible_inventory.json`; `tofu-unifi` still reads its own
> `deployment/*.json`; Ansible still resolves hosts from the published
> inventory artifact. That gap is the defect being closed, not a design to
> preserve.
>
> **Authority flip in design (not started).** A separately-gated effort will
> move network intent (IPs, VLANs, DNS names, firewall intent) to Nautobot as
> the source of truth, leaving this repo authoritative for **guest lifecycle
> only**. Until Phase 2 is explicitly gated open, this repo remains the source
> of truth described here — do **not** shrink `deployment.json` network fields
> or retire the published `ansible_inventory.json`. Design + boundary:
> [Phase-2 authority-flip design](https://github.com/dryvist/ansible-proxmox-apps/blob/develop/docs/nautobot/phase2-authority-flip-design.md).

- **IP derivation**: every IP is `cidrhost(network_cidrs[vlan], vm_id)`. Example
  CIDRs are `192.168.<vlan_id>.0/24`, so a compute-VLAN (id 10) VM 42 →
  `192.168.10.42`. Never hardcode IPs in any repo — they come from terraform output.
- **Pipeline constants**: `modules/proxmox-stack/constants*.tf` define
  `pipeline_constants` with service / syslog / netflow / notification /
  vector-db / AI-log port mappings, surfaced via
  `ansible_inventory.constants` in `outputs.tf`. There is no root `locals.tf`.
- **Firewall model**: default-deny, two independent layers. The guest layer
  (`modules/firewall/*.tf`) is live today — every VM/LXC gets
  `input_policy = DROP` / `output_policy = DROP` plus per-service allow
  rules keyed off `pipeline_constants` ports. The network layer (`tofu-unifi`
  inter-VLAN `LAN_IN` rules) is written to the same model but not yet
  enforced (blocked on a provider/controller rule-index gap — see that
  repo's docs). Add a new inter-VLAN flow at the guest layer first; the
  UniFi rule is written alongside it but ships `enabled = false` until the
  gap closes.
- **Media appdata**: each app's persistent config lives on its own
  `<pool>/appdata/<app>` ZFS dataset (declared in `node_storage.zfs_pools`),
  bind-mounted by `ansible-proxmox`'s `media_lxc_features` — never on the
  container's ephemeral rootfs. Sortarr (the read-only insights dashboard)
  follows this pattern with no `/data` media mount, since it never touches
  media files directly.

## Downstream repos

All three consumers resolve the inventory the same way (their
`load_tofu.yml`): `TOFU_INVENTORY_PATH` (explicit pin) → the **S3 published
artifact** (written natively by every apply via `aws_s3_object`; fetched with
`amazon.aws` modules — AWS read creds only, no checkout, no toolchain) → the
local gitignored cache. See `docs/INVENTORY_PUBLISHING.md`.

| Repo | Consumes | Purpose |
| --- | --- | --- |
| `ansible-proxmox` | `ansible_inventory` (host_services, node_storage, nodes) | Host config (kernel, ZFS, monitoring, NAS/Samba) |
| `ansible-proxmox-apps` | `ansible_inventory` (containers, docker_vms, constants, ingress) | Cribl, HAProxy, DNS, honeypots (`opencanary`, `apprise`, `tpot` roles — see `docs/HONEYPOTS.md`), etc. |
| `ansible-splunk` | `ansible_inventory` (splunk_vm + the Splunk-native HA cluster peers in `vms`) | Splunk Enterprise (Docker AIO, retiring) and the HA cluster; incl. the `honeypot` index |
| `ansible-proxmox-ai` | `ansible_inventory` (containers, nodes) | Local ML/LLM serving, observability, and AI agents |

## Ansible execution (Semaphore)

Ansible playbooks for all downstream repos are executed centrally by Semaphore,
which acts as the automated Ansible management plane. Semaphore runs as a
Docker container on the `iac-platform` VM.
The Semaphore environment itself (projects, repositories, inventories,
schedules, and job templates) is managed completely via infrastructure-as-code
in the `iac-platform` repo (`iac-platform-semaphore` workspace).

- **Execution identity**: Semaphore jobs authenticate via short-lived SSH
  certificates, minted by exchanging an OpenBao AppRole identity
  (`OPENBAO_APPROLE_ANSIBLE_ROLE_ID` and `SECRET_ID`) for a signed certificate
  at run time.
- **Triggering runs**: Routine validation and drift reports run on Semaphore
  schedules. Applies are triggered via the Semaphore UI
  (`https://semaphore.<domain>`) or its API. Manual, local CLI execution
  (`doppler run -- ./scripts/run-ansible.sh`) is still possible but is
  reserved for break-glass or development.

## Inventory publish + sync (automatic)

Every apply publishes the inventory **natively** to the versioned state bucket
(`inventory_publish.tf`, `aws_s3_object.ansible_inventory`). `lifecycle`
preconditions on that resource validate the required inventory keys — mirroring
the ansible-proxmox-apps JSON schema — before the write, so a partial/invalid
output is rejected before anything reaches S3. The former private-data-repo
versioned-mirror PR is retired; bucket versioning on `iac-inventory` is the
safety net for a bad publish instead (see `docs/INVENTORY_PUBLISHING.md`). Each
consumer's local gitignored cache remains an offline fallback, refreshed by its
own `load_tofu.yml` resolver — not by this repo.

To sync manually after importing state without applying, see
`docs/ARCHITECTURE.md`.
