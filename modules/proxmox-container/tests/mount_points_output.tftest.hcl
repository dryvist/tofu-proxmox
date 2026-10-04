# Does the container_mount_points output survive a container that carries two
# mounts at one path, and a container with no mounts at all?
#
# Mounts are applied after creation by Ansible roles, and `mount_point` is in
# the resource's ignore_changes, so a refreshed container can list a path
# twice. The output is evaluated on every plan; a duplicate object key in it
# would fail the whole plan, not just the verification it exists for.
#
# Assertions read the module OUTPUT, the thing that errors.

mock_provider "proxmox" {}

variables {
  domain            = "example.test"
  environment       = "test"
  default_datastore = "local-zfs"

  containers = {
    twice_mounted = {
      vm_id            = 605040
      node_name        = "proxmox-1"
      hostname         = "twice-mounted"
      template_file_id = "local:vztmpl/example.tar.zst"
      mount_points = [
        {
          volume = "local-zfs:120"
          path   = "/var/lib/models"
        },
        {
          volume    = "local-zfs:120"
          path      = "/var/lib/models"
          read_only = true
        },
        {
          volume = "local-zfs:8"
          path   = "/data"
        },
      ]
    }
    unmounted = {
      vm_id            = 605041
      node_name        = "proxmox-1"
      hostname         = "unmounted"
      template_file_id = "local:vztmpl/example.tar.zst"
    }
  }
}

run "two_mounts_at_one_path_report_the_later_one" {
  command = plan

  assert {
    condition     = output.container_mount_points["twice_mounted"]["/var/lib/models"] == true
    error_message = "with two mounts at one path the output must report the later one, the mount the guest actually sees."
  }

  assert {
    condition     = output.container_mount_points["twice_mounted"]["/data"] == false
    error_message = "a path mounted once must still report its own read_only flag."
  }
}

run "a_container_without_mounts_reports_none" {
  command = plan

  assert {
    condition     = length(output.container_mount_points["unmounted"]) == 0
    error_message = "a container with no mount_points must publish an empty map."
  }
}
