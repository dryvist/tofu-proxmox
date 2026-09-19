# Does boot_disk.replicate / additional_disks[].replicate actually reach the
# VM resource? (Incident: Zammad #1000415 — an ephemeral CI-runner VM had no
# way to opt a disk out of replication, so its churn was pinned in
# replication snapshots and a single-disk ZFS pool filled up.)
#
# Assertions read the attribute ON THE RESOURCE, not the variable: a test
# against `var.vms[...]` would still pass with the wiring deleted from main.tf.

mock_provider "proxmox" {}

variables {
  domain                  = "example.test"
  environment             = "test"
  default_datastore       = "local-zfs"
  proxmox_ssh_username    = "root"
  proxmox_ssh_private_key = "not-a-real-key"

  vms = {
    ephemeral = {
      vm_id     = 262
      name      = "ephemeral"
      node_name = "proxmox-1"
      boot_disk = {
        datastore_id = "local-zfs"
        size         = 32
        replicate    = false
      }
      additional_disks = [
        {
          datastore_id = "local-zfs"
          interface    = "scsi1"
          size         = 100
          replicate    = false
        }
      ]
      user_account = {
        username = "test"
        password = "test"
        keys     = []
      }
    }
    replicated = {
      vm_id     = 263
      name      = "replicated"
      node_name = "proxmox-1"
      user_account = {
        username = "test"
        password = "test"
        keys     = []
      }
    }
  }
}

run "replicate_false_reaches_the_boot_disk" {
  command = plan

  assert {
    condition     = proxmox_virtual_environment_vm.vms["ephemeral"].disk[0].replicate == false
    error_message = "boot_disk.replicate=false did not reach the VM resource — an ephemeral guest's disk would still be pinned in replication snapshots."
  }
}

run "replicate_false_reaches_additional_disks" {
  command = plan

  assert {
    condition     = proxmox_virtual_environment_vm.vms["ephemeral"].disk[1].replicate == false
    error_message = "additional_disks[].replicate=false did not reach the VM resource."
  }
}

# Negative control: an undeclared replicate must still default to true, or
# every other guest in the estate silently stops replicating.
run "replicate_defaults_true_when_not_declared" {
  command = plan

  assert {
    condition     = proxmox_virtual_environment_vm.vms["replicated"].disk[0].replicate == true
    error_message = "replicate defaulted to something other than true — an undeclared guest must keep its existing replication behavior."
  }
}
