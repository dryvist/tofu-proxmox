# Does a mount_point's read_only flag reach the container resource, and does
# leaving it unset keep the mount read-write?
#
# The llama_cpp Ansible role asserts /var/lib/llama-cpp/models is mounted `ro`
# before it will deploy the serving unit — a guest must never write model
# weights locally. Without this attribute the module had no way to express
# that, so every LXC mount_point landed rw regardless of what the guest needed.
#
# Assertions read the attribute ON THE RESOURCE, not the variable: a test
# against `var.containers[...]` would still pass with the wiring removed from
# main.tf.

mock_provider "proxmox" {}

variables {
  domain            = "example.test"
  environment       = "test"
  default_datastore = "local-zfs"

  containers = {
    models_ro = {
      vm_id            = 605030
      node_name        = "proxmox-1"
      hostname         = "models-ro"
      template_file_id = "local:vztmpl/example.tar.zst"
      mount_points = [
        {
          volume    = "/models-pool/llama-cpp"
          path      = "/var/lib/llama-cpp/models"
          read_only = true
        },
      ]
    }
    # No override: negative control below proves the default stays rw.
    data_rw = {
      vm_id            = 605031
      node_name        = "proxmox-1"
      hostname         = "data-rw"
      template_file_id = "local:vztmpl/example.tar.zst"
      mount_points = [
        {
          volume = "/data-pool/example"
          path   = "/data"
        },
      ]
    }
  }
}

run "read_only_mount_reaches_the_resource" {
  command = plan

  assert {
    condition     = proxmox_virtual_environment_container.containers["models_ro"].mount_point[0].read_only == true
    error_message = "read_only did not reach the container resource — a guest that must never write model weights would still get a writable mount."
  }
}

# Negative control. Without this the test above would still pass if the
# module hard-coded read_only = true on every mount, which would break every
# other guest's writable data mount.
run "unset_read_only_keeps_the_mount_writable" {
  command = plan

  assert {
    condition     = proxmox_virtual_environment_container.containers["data_rw"].mount_point[0].read_only == false
    error_message = "a mount_point with no read_only override no longer defaults to writable; adding the attribute changed guests that never declared one."
  }
}
