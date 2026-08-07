# Windows VDI templates

Builds Windows templates that OpenTofu then clones. One template per OS:
`win10`, `win11`, `win25`. The templates are **not** sysprep-generalized — see
[What a build produces](#what-a-build-produces) for why.

This directory is deliberately separate from `../` — `packer build .` builds
every source it finds, so keeping these apart stops a Windows build from also
rebuilding unrelated images.

## Where to run it

On a LAN host, not a macOS workstation. The builder needs the Proxmox API *and*
a WinRM connection to the VM it is creating; macOS Local Network privacy denies
the second, and the failure presents as a connection timeout rather than a
permission error. See [../../docs/EXECUTION_HOSTS.md](../../docs/EXECUTION_HOSTS.md).

`packer` itself is taken from `PATH`, else nix, else docker — whichever the host
has. Nothing needs installing.

## Credentials

Supplied by `../../scripts/build-windows-templates.sh`, which reads OpenBao at
call time and exports `PKR_VAR_*`. Nothing is written to disk and no
`-var-file` is used.

The `packer` AppRole grants exactly the two reads a build needs, and nothing
else — a write to either path is refused. The OpenBao converge in
`ansible-proxmox-apps` mints its `role_id`/`secret_id`; both are published to
Doppler tier-0, so `doppler run` supplies them and no file holds them.

```bash
export BAO_ADDR=...          # or BAO_TOKEN, if you have one
export PROXMOX_NODE=...      # node the VDI guests clone onto
# OPENBAO_APPROLE_PACKER_ROLE_ID and _SECRET_ID come from `doppler run`
```

Prefer the OpenBao ingress name for `BAO_ADDR`. The converge writes a node
address into its own output, which does not survive that node being down.

`PROXMOX_NODE` is a build parameter, not a credential — templates are node-local
unless the storage is shared, so it must name the node the clones live on.

## Running a build

```bash
../../scripts/build-windows-templates.sh init          # once per host
../../scripts/build-windows-templates.sh validate
../../scripts/build-windows-templates.sh build win11   # 8-20 min
```

`build` requires an image name. There is no "build everything" form.

Build one at a time. Each build boots a VM with the same memory the finished
guest gets, so two at once can exhaust a node.

## What a build produces

A template in the 9xxx VMID band. Packer generates the answer ISO from
`answer/autounattend.pkrtpl.xml`, attaches it alongside the virtio driver ISO,
and removes it afterwards.

One answer file, `autounattend.pkrtpl.xml`, applied during install. It sets up
virtio-scsi in WinPE, the guest tools, the Administrator password, WinRM and
RDP — and because the template is **not** sysprep-generalized, all of that is
captured into the image and inherited by every clone verbatim.

`sysprep /generalize` was removed deliberately. It buys a unique SID and machine
name per clone, which matters for domain join, WSUS/SCCM and KMS activation —
none of which exist here. What it cost was most of this build's failure surface:
it refuses on a BitLocker-encrypted volume, fails `0x80070005` when its answer
file is staged at the path it caches into, races the builder's own power-off,
and does not block a PowerShell `&`, so a half-resealed image converts cleanly
and misbehaves later. The trade is that clones share a SID and boot with the
template's machine name; rename via configuration management if that ever
matters.

The build asserts the guest agent service and an up network adapter both exist
before capturing. A template whose clones would be unreachable fails the build
instead of being captured.

## Consuming a template

Set `clone_template` on the VM in `deployment.json`:

```json
"clone_template": { "template_id": 9210, "full": false }
```

`full` defaults to `true`, which copies the template's whole disk up front —
9-12 GB per clone for a Windows image. On a small boot pool two of those can
exhaust it. `full: false` makes a **linked clone**: copy-on-write off the
template's snapshot, starting near zero and growing only with what the guest
writes. That is the usual choice for VDI, where guests are disposable and the
template is the artifact worth keeping.

The trade: a template cannot be deleted while a linked clone of it exists, and
the clone must live on the same storage as its template.

`clone` is in `ignore_changes` in `modules/proxmox-vm`, so adding it to a VM that
already exists is a no-op — the VM must be recreated to become a clone.

### Always set `cpu_type` and `os_type` too

The `vms` object type defaults to `cpu_type = "x86-64-v2-AES"` and
`os_type = "l26"`. Both are Linux defaults, and nothing warns when they land on
a Windows guest. A template built with `cpu_type = "host"` then clones onto
different emulated silicon than Windows installed on, and **the clone hangs
immediately after `bootmgfw.efi`** — no logo, no spinner, just a black screen
that looks like a broken disk or a bad boot order and is neither.

Declare them on every Windows guest:

```json
"cpu_type": "host",
"os_type": "win11"
```

Use `win10` for a Windows 10 image; Windows Server 2025 uses `win11`.

To tell a hung clone from a slow one, sample the guest's disk counters twice a
minute apart. Frozen counters mean it is not booting. Two failed boots also drop
Windows into recovery, which does not clear itself once the CPU is corrected —
the console needs two keypresses to leave it.

### Starting a cloned guest

The VDI guests are declared `on_boot: false` and `started: false`, so neither a
node reboot nor an apply powers them on. Starting them is a human action.
`started` is ignored after creation, so a guest an operator starts by hand stays
running and no later apply shuts it down. Both fields are published in
`ansible_inventory`, so a converge can skip a guest that is switched off.
