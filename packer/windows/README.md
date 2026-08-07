# Windows VDI templates

Builds generalized Windows templates that OpenTofu then clones. One template per
OS: `win10`, `win11`, `win25`.

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
../../scripts/build-windows-templates.sh build win11   # 30-60 min
```

`build` requires an image name. There is no "build everything" form.

## What a build produces

A sysprep-generalized template in the 9xxx VMID band, so each clone gets its own
SID and can still be domain-joined. Packer generates the answer ISO from
`answer/*.pkrtpl.xml`, attaches it alongside the virtio driver ISO, and removes
it afterwards.

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

Set `clone_template = { template_id = <vmid> }` on the VM in `deployment.json`.

`clone` is in `ignore_changes` in `modules/proxmox-vm`, so adding it to a VM that
already exists is a no-op — the VM must be recreated to become a clone.
