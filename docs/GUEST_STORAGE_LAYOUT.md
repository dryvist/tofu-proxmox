# Guest storage layout

> Split out of `INFRASTRUCTURE_NUMBERING.md` (shared 12 KB file-size gate) —
> same authority, different file.

## Cribl persistent-queue disks

Cribl Stream and Cribl Edge containers carry a separate data disk for the on-disk persistent
queue (mounted at `/opt/cribl/data`): a small root disk for OS + application, plus a larger
data disk so a HAProxy/Cribl outage buffers instead of dropping. Ansible formats and mounts
the data disk; see the Cribl roles in the downstream apps repo.

## Splunk VM disk layout

The Splunk VM carries a boot disk, a legacy data disk, and two tiered storage
disks:

- **Boot disk**: OS, Splunk application, configuration. Declared `virtio0`. The
  live interface and size are managed outside this repo; `lifecycle.ignore_changes`
  covers the whole `disk` attribute, so the declared block is not authoritative.
- **Legacy data disk (`virtio1`, 200G)**: current Splunk index storage, mounted
  at `/opt/splunk`. Transitional — kept attached until a separate migration
  moves data onto the tiered disks below. The mount point matters: the volume
  covers all of `/opt/splunk`, not just `/opt/splunk/var`, so a capacity check
  aimed at the deeper path measures the wrong filesystem.
- **`fast-splunk` (`virtio2`)**: hot + warm buckets on the fast/NVMe tier
  (`datastore_id = fast-splunk`, `backup = false` by design). Index data is
  reconstructible, and block-level backups of it would roughly double the
  storage consumed for no resilience gain. Durability for data worth keeping
  comes from the frozen tier, not from backing up the index volumes.
- **`bulk-splunk` (`virtio3`)**: cold buckets on the non-RAID cold tier
  (`datastore_id = bulk-splunk`, `backup = false` by design; archived to
  Backblaze B2).

Disk sizes are set in `deployment.json`: `splunk_boot_disk_size`,
`splunk_data_disk_size` (legacy `virtio1`), `splunk_fast_disk_size` (default
1024), and `splunk_bulk_disk_size` (default 2048). The tiered disks are declared
but do not attach until the disk-drift reconciliation completes (see the drift
doc). See [`ARCHITECTURE.md`](./ARCHITECTURE.md) for the per-tier RAID/backup
posture.
