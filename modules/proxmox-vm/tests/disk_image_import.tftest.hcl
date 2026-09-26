# Does `disk_image` actually reach a download_file resource and the VM's
# boot disk (import_from)?
#
# Same silent-drop risk as the other passthrough tests in this suite: assert
# on the RESOURCE, not the variable, so a deleted wiring line fails the test
# instead of a schema check that never exercises main.tf.

mock_provider "proxmox" {}

variables {
  domain                  = "example.test"
  environment             = "test"
  default_datastore       = "local-zfs"
  proxmox_user            = "root"
  proxmox_ssh_private_key = "not-a-real-key"

  vms = {
    appliance = {
      vm_id     = 120
      name      = "appliance"
      node_name = "proxmox-1"
      bios      = "ovmf"
      machine   = "q35"
      boot_disk = {
        datastore_id = "local-zfs"
      }
      efi_disk = {
        datastore_id = "local-zfs"
      }
      disk_image = {
        url                = "https://example.test/appliance.qcow2"
        file_name          = "appliance.qcow2"
        checksum           = "deadbeef"
        checksum_algorithm = "sha256"
      }
      user_account = {
        username = "test"
        password = "test"
        keys     = []
      }
    }
    cloned = {
      vm_id     = 121
      name      = "cloned"
      node_name = "proxmox-1"
      clone_template = {
        template_id = 9210
      }
      user_account = {
        username = "test"
        password = "test"
        keys     = []
      }
    }
  }
}

run "download_file_reaches_the_vm_node" {
  command = plan

  assert {
    condition     = proxmox_download_file.disk_image["appliance"].node_name == "proxmox-1"
    error_message = "disk_image did not create a download_file resource on the VM's own node."
  }

  assert {
    condition     = proxmox_download_file.disk_image["appliance"].content_type == "import"
    error_message = "disk_image download must use content_type = import, or PVE rejects it as a disk-import source."
  }
}

run "import_from_reaches_the_boot_disk" {
  command = plan

  assert {
    condition     = proxmox_virtual_environment_vm.vms["appliance"].disk[0].import_from == "local-zfs:import/appliance.qcow2"
    error_message = "disk_image did not reach disk.import_from on the boot disk — the VM would boot an empty disk instead of the imported image."
  }
}

# Negative control: a VM with no disk_image must not create a download_file
# resource or set import_from, or every clone/fresh-install VM in the estate
# would suddenly import something.
run "no_disk_image_means_no_import" {
  command = plan

  assert {
    condition     = !contains(keys(proxmox_download_file.disk_image), "cloned")
    error_message = "a VM without disk_image must not get a download_file resource."
  }

  assert {
    condition     = proxmox_virtual_environment_vm.vms["cloned"].disk[0].import_from == null
    error_message = "import_from must stay null for a VM that does not declare disk_image."
  }
}

# disk_image and clone_template are mutually exclusive (see variables.tf
# validation) — declaring both must fail at plan, not build an ambiguous VM.
run "disk_image_and_clone_template_together_is_rejected" {
  command = plan

  variables {
    vms = {
      both = {
        vm_id     = 122
        name      = "both"
        node_name = "proxmox-1"
        clone_template = {
          template_id = 9210
        }
        disk_image = {
          url       = "https://example.test/appliance.qcow2"
          file_name = "appliance.qcow2"
        }
        user_account = {
          username = "test"
          password = "test"
          keys     = []
        }
      }
    }
  }

  expect_failures = [
    var.vms,
  ]
}

# The provider's download_file resource cannot decompress .xz — only
# gz | lzo | zst | bz2. This must be rejected at plan, not surface as an
# opaque PVE API error mid-apply.
run "xz_decompression_is_rejected" {
  command = plan

  variables {
    vms = {
      bad_algo = {
        vm_id     = 123
        name      = "bad-algo"
        node_name = "proxmox-1"
        disk_image = {
          url                     = "https://example.test/appliance.qcow2.xz"
          file_name               = "appliance.qcow2"
          decompression_algorithm = "xz"
        }
        user_account = {
          username = "test"
          password = "test"
          keys     = []
        }
      }
    }
  }

  expect_failures = [
    var.vms,
  ]
}
