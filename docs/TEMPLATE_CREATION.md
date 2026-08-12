# VM templates

Guests are cloned from templates. Nothing here is built by hand on a node — a
template that exists only because someone ran `qm` cannot be rebuilt after a
node is lost.

## Where each template comes from

| Template | Built by | Declared in |
| --- | --- | --- |
| Debian cloud-init base (9001) | OpenTofu | `modules/proxmox-stack/base_templates.tf` |
| Windows 10 / 11 / Server 2025 (9210-9212) | Packer | the `packer-proxmox` repository |
| Splunk Docker (9200) | Packer | the `packer-proxmox` repository |

The Debian base is OpenTofu rather than Packer because it imports a cloud image
instead of running an installer, and no Packer builder imports a disk image.
The Windows and Splunk images do run a real install or provisioning pass, which
is exactly what Packer is for.

## Changing the Debian base template

Everything is a variable in `modules/proxmox-stack/variables-storage.tf`:
`debian_template_id`, `debian_template_name`, `debian_cloudimg_file_name` and
`debian_cloudimg_url`.

To move to a new Debian release, change the URL and the file name together. The
file name is what the download resource keys on, so a new name is what triggers
the re-download; pointing a new release at an old file name silently keeps the
old image.

Roll forward by declaring the new template under a new `debian_template_id`,
switching guests to it, and removing the old one once nothing clones from it.

## Consuming a template

Set `clone_template` on the VM in `deployment.json`:

```json
"clone_template": { "template_id": 9001, "full": false }
```

`full` defaults to `true`, which copies the template's whole disk up front.
`full: false` makes a **linked clone**: copy-on-write off the template's
snapshot, starting near zero and growing only with what the guest writes.

The trade-offs: a template cannot be deleted while a linked clone of it exists,
and the clone must live on the same storage as its template.

`clone` is in `ignore_changes` in `modules/proxmox-vm`, so adding it to a VM that
already exists is a no-op — the VM must be recreated to become a clone.

Cloud-init then applies the network configuration, user account, SSH keys and
hostname from the guest's own `deployment.json` entry.

### Windows guests: always set `cpu_type` and `os_type`

The `vms` object type defaults to `cpu_type = "x86-64-v2-AES"` and
`os_type = "l26"`. Both are Linux defaults and nothing warns when they land on a
Windows guest. A Windows clone that inherits them **hangs immediately after
`bootmgfw.efi`** — no logo, no spinner, just a black screen that looks like a
broken disk or a bad boot order and is neither.

```json
"cpu_type": "host",
"os_type": "win11"
```

Use `win10` for a Windows 10 image; Windows Server 2025 uses `win11`.

To tell a hung clone from a slow one, sample the guest's disk counters twice a
minute apart — frozen counters mean it is not booting. Two failed boots also drop
Windows into recovery, which does not clear itself once the CPU type is
corrected; the console needs two keypresses to leave it.

## References

- [Debian cloud images](https://cloud.debian.org/images/cloud/)
- [Proxmox cloud-init support](https://pve.proxmox.com/wiki/Cloud-Init_Support)
