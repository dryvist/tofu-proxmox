# Tests for the pool-capacity guard (checks-node-storage-capacity.tf).
#
# Each case gets BOTH a must-fail and a must-pass control, per the convention in
# node_storage_smb.tftest.hcl. A negative test alone cannot tell a working guard
# from one that rejects everything, and a positive test alone cannot tell a
# working guard from one that is never evaluated.
#
# The pair that matters most is six_wide_pool_accepted /
# same_quotas_rejected_at_five_wide: IDENTICAL quotas, differing only in the
# declared width. That is the real scenario -- a pool loses a device and is not
# immediately rebuilt -- and it is the case a positive-only suite would pass
# while the guard did nothing.

# Mocks and the root module's required inputs, matching the preamble every
# other suite in this directory carries. None of it is exercised by these runs
# -- the guard is pure declaration arithmetic -- it is here only because a
# `plan` cannot start without it.

mock_provider "proxmox" {
  mock_data "proxmox_virtual_environment_datastores" {
    defaults = {
      datastores = [
        { id = "local", type = "dir", content_types = ["iso", "vztmpl", "backup"] },
        { id = "local-zfs", type = "zfspool", content_types = ["images", "rootdir"] },
      ]
    }
  }
}
mock_provider "tls" {}
mock_provider "random" {}
mock_provider "aws" {}
mock_provider "null" {}

override_module {
  target = module.storage
  outputs = {
    cloud_init_file_id   = null
    datastores_available = {}
    storage_validated    = true
  }
}

override_module {
  target = module.splunk_vm
  outputs = {
    vm_id       = 200
    name        = "splunk-aio"
    ip_address  = "192.0.2.200"
    mac_address = "BC:24:11:00:00:C8"
    tiered_disks = {
      fast = { datastore_id = "fast-splunk", interface = "virtio2", size = 1024, backup = true }
      bulk = { datastore_id = "bulk-splunk", interface = "virtio3", size = 2048, backup = false }
    }
  }
}

override_module {
  target = module.acme_certificates
  outputs = {
    acme_accounts = {}
    dns_plugins   = {}
    certificates  = {}
  }
}

variables {
  vm_ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestKeyData test@test"
  # proxmox_ssh_private_key validates only on a leading "-----BEGIN", so the
  # fixture needs that prefix and nothing else. Deliberately NOT shaped like a
  # real key banner: a fixture that mimics one is indistinguishable from a
  # leaked key to every scanner that reads this repo, and the sibling suites
  # that do mimic one should be moved to this form too.
  proxmox_ssh_private_key = "-----BEGIN TEST FIXTURE, NOT A KEY-----"
  network_cidrs           = { for name, id in var.vlan_ids : name => "192.168.${id}.0/24" }
  node_storage            = {}
}

# --- Positive control: quotas that fit a six-wide raidz2 are accepted ---
#
# 4 data devices x 5.46T x 31/32 = 21.15 TiB usable; 17 TiB declared.

run "six_wide_pool_accepted" {
  command = plan

  variables {
    node_storage = {
      test-node = {
        pools = {
          poolA = {
            topology = { type = "raidz2", width = 6, ashift = 12, device_size = "5.46T" }
            datasets = {
              alpha = { quota = "15T" }
              beta  = { quota = "1T" }
              gamma = { quota = "1T" }
            }
          }
        }
      }
    }
  }

  assert {
    condition     = length(local.overcommitted_storage_pools) == 0
    error_message = "A six-wide raidz2 of 5.46T devices holds 21.15 TiB usable; 17 TiB of quota must be accepted."
  }
}

# --- Negative: THE SAME QUOTAS, one device narrower, must be rejected ---
#
# 3 data devices x 5.46T x 31/32 = 15.86 TiB usable; 17 TiB declared.

run "same_quotas_rejected_at_five_wide" {
  command = plan

  variables {
    node_storage = {
      test-node = {
        pools = {
          poolA = {
            topology = { type = "raidz2", width = 5, ashift = 12, device_size = "5.46T" }
            datasets = {
              alpha = { quota = "15T" }
              beta  = { quota = "1T" }
              gamma = { quota = "1T" }
            }
          }
        }
      }
    }
  }

  expect_failures = [
    terraform_data.node_storage_capacity_guard,
  ]
}

# --- A pool that declares no device_size is NOT checked, rather than guessed ---
#
# Every pool in the estate predates this field, so opting in by declaration is
# what keeps adding the guard from failing plans for pools nobody has measured.
# Without this case, a guard that silently checked nothing would still pass the
# positive control above.

run "pool_without_device_size_is_unchecked" {
  command = plan

  variables {
    node_storage = {
      test-node = {
        pools = {
          poolA = {
            topology = { type = "raidz2", width = 2 }
            datasets = {
              alpha = { quota = "999T" }
            }
          }
        }
      }
    }
  }

  assert {
    condition     = length(local.checkable_storage_pools) == 0
    error_message = "A pool without device_size must be excluded from the capacity check, not evaluated against a guessed capacity."
  }
}

# --- draid carries its geometry in the vdev name, not in topology ---
#
# Checking it would mean inventing a data/parity/spare split this schema does
# not carry, so it is excluded on purpose. Same reasoning as device_size above.

run "draid_pool_is_unchecked" {
  command = plan

  variables {
    node_storage = {
      test-node = {
        pools = {
          poolA = {
            topology = { type = "draid", width = 12, device_size = "5.46T" }
            datasets = {
              alpha = { quota = "999T" }
            }
          }
        }
      }
    }
  }

  assert {
    condition     = length(local.checkable_storage_pools) == 0
    error_message = "draid geometry is not derivable from topology; the pool must go unchecked rather than be judged against an invented capacity."
  }
}

# --- A mirror's usable capacity is ONE device, not width minus parity ---
#
# Applying the raidz formula to a mirror would report a 3-way mirror as holding
# two devices' worth, i.e. double its real capacity, so the mirror branch needs
# its own pair.

run "mirror_capacity_is_one_device" {
  command = plan

  variables {
    node_storage = {
      test-node = {
        pools = {
          poolB = {
            topology = { type = "mirror", width = 3, device_size = "1T" }
            datasets = {
              # 1500G fits under "width minus parity" (2 devices) but NOT under
              # a correct mirror capacity of one device x 31/32 = 0.97 TiB.
              alpha = { quota = "1500G" }
            }
          }
        }
      }
    }
  }

  expect_failures = [
    terraform_data.node_storage_capacity_guard,
  ]
}

run "mirror_within_one_device_accepted" {
  command = plan

  variables {
    node_storage = {
      test-node = {
        pools = {
          poolB = {
            topology = { type = "mirror", width = 3, device_size = "1T" }
            datasets = {
              alpha = { quota = "900G" }
            }
          }
        }
      }
    }
  }

  assert {
    condition     = length(local.overcommitted_storage_pools) == 0
    error_message = "900G must fit a 3-way mirror of 1T devices (0.97 TiB usable)."
  }
}

# --- A child dataset's quota is NOT added to its parent's ---
#
# The child's usage already counts against every quota above it, so summing
# both double-counts the child. Sized so ONLY the correct sum fits, which is
# what makes this case discriminate: 3 data devices x 1T x 31/32 = 2.91 TiB
# usable, against a naive sum of 2.93 TiB (rejects) and a correct sum of
# 1.95 TiB (accepts).

run "child_quota_not_double_counted" {
  command = plan

  variables {
    node_storage = {
      test-node = {
        pools = {
          poolA = {
            topology = { type = "raidz2", width = 5, device_size = "1T" }
            datasets = {
              alpha = { quota = "1500G" }
              # Both of these are bounded by alpha and must contribute nothing.
              # The grandchild sits under an UNQUOTA'D middle dataset, so a
              # parent-only check would miss it where an ancestor check does not.
              "alpha/child"    = { quota = "500G" }
              "alpha/mid/leaf" = { quota = "500G" }
              beta             = { quota = "500G" }
            }
          }
        }
      }
    }
  }

  assert {
    condition     = length(local.overcommitted_storage_pools) == 0
    error_message = "A child's quota must not be added to an ancestor's; alpha at 1500G already bounds everything beneath it, including a grandchild under an unquota'd middle dataset."
  }
}

# --- ...but a SIBLING's quota still counts ---
#
# Same shape, except the second 1500G dataset is a peer rather than a child, so
# the sum is genuinely 3.0 TiB against 2.90 TiB usable and must be rejected.
# Without this pair, an ancestor filter that swallowed every quota would pass
# the case above while checking nothing.

run "sibling_quotas_still_summed" {
  command = plan

  variables {
    node_storage = {
      test-node = {
        pools = {
          poolA = {
            topology = { type = "raidz2", width = 5, device_size = "1T" }
            datasets = {
              alpha         = { quota = "1500G" }
              "alpha/child" = { quota = "500G" }
              beta          = { quota = "1500G" }
              gamma         = { quota = "500G" }
            }
          }
        }
      }
    }
  }

  expect_failures = [
    terraform_data.node_storage_capacity_guard,
  ]
}

# --- Datasets that declare no quota at all must not break the sum ---
#
# sum() rejects an empty list, so a pool whose datasets are all unquotaed is a
# crash rather than a finding unless the empty case is handled.

run "pool_with_no_quotas_is_accepted" {
  command = plan

  variables {
    node_storage = {
      test-node = {
        pools = {
          poolA = {
            topology = { type = "raidz2", width = 6, device_size = "5.46T" }
            datasets = {
              alpha = {}
              beta  = {}
            }
          }
        }
      }
    }
  }

  assert {
    condition     = length(local.overcommitted_storage_pools) == 0
    error_message = "A pool whose datasets declare no quota must pass, not error on an empty sum."
  }
}
