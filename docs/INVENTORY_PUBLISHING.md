# Native Inventory Publishing

Every full `tofu-proxmox` apply publishes `local.ansible_inventory` to
`s3://iac-inventory/ansible_inventory.json` on homelab RustFS through the
`aws_s3_object` resource. The RustFS provider credentials come from the native
OpenBao object-storage path and remain ephemeral.

The publish is part of the OpenTofu graph, not an after-hook. `lifecycle`
preconditions on `aws_s3_object.ansible_inventory` reject incomplete
containers, VMs, docker VMs, the Splunk VM, pipeline constants, or ingress
records — mirroring the ansible-proxmox-apps JSON schema's required keys —
before the object is written. Downstream Ansible repositories read the
versioned object with scoped native OpenBao credentials and retain their
local cache only as an offline fallback.

The private-data-repo versioned-mirror PR (the old `scripts/sync-inventory.sh`
after-hook) is retired along with Terragrunt. Object versioning on the
`iac-inventory` RustFS bucket is the replacement history/rollback mechanism.

Never use a targeted apply: excluding the publisher could leave consumers on
an older contract. A full Terrakube workspace run is the only publish boundary.

During migration, the former AWS inventory object is intentionally forgotten
without destruction. Retire that orphan only after every consumer proves the
RustFS path through its end-to-end validation.

## VDI split-tunnel keys

A guest running a VPN client installs its own default route, so the guest's
replies to anything outside its own subnet leave through the tunnel instead of
the LAN. Inbound connections still arrive, which makes the result look like a
broken guest rather than a routing change: established sessions drop and
configuration management can no longer reach it.

Two keys carry what a consumer needs to pin chosen networks back to the LAN:

| Key | Scope | Meaning |
| --- | --- | --- |
| `vms.<name>.gateway` | per VM | The guest's own LAN gateway. Published because the guest cannot report it once a VPN client owns the default route. `null` for DHCP-first guests. |
| `vdi_preserved_cidrs` | top level | Subnets that stay reachable over the LAN, resolved from the `vdi_preserved_vlans` keys in the desired state against `network_cidrs`. Empty disables the behaviour. |

`vdi_preserved_vlans` is a short opt-in list rather than every VLAN on purpose:
routing an entire estate past the tunnel breaks whatever the VPN exists to
reach as soon as a network behind it overlaps one of those subnets. List only
what must survive — at minimum the operator's own network and the one
configuration management runs from, without which no converge can reach the
guest while the VPN is connected.

A publish precondition rejects a guest tagged `vdi` that has no gateway, so a
DHCP-first VDI guest fails the plan rather than publishing destinations with
nothing to point them at. `ansible-proxmox-apps` consumes both keys in its
`vdi_local_routes` role, applied to every guest carrying the `vdi` tag.
