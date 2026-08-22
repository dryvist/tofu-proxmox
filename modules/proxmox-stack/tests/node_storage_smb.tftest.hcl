# Tests for the node_storage SMB share declaration.
#
# Each validation gets BOTH a must-fail case and a must-pass control. A
# negative test alone cannot tell a working guard from one that rejects
# everything, and a positive test alone cannot tell a working guard from one
# that is never evaluated.
#
# All runs use mock providers (no real infrastructure needed).

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
  vm_ssh_public_key       = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestKeyData test@test"
  proxmox_ssh_private_key = "-----BEGIN OPENSSH PRIVATE KEY-----\ntest\n-----END OPENSSH PRIVATE KEY-----"
  network_cidrs           = { for name, id in var.vlan_ids : name => "192.168.${id}.0/24" }
}

# --- Positive control: a fully-formed SMB declaration is accepted ---

run "valid_smb_datasets_accepted" {
  command = plan

  variables {
    node_storage = {
      test-node = {
        smb = {
          group_name = "nas"
          managed_users = [{
            secret_prefix = "smb_user"
            unix_groups   = ["nas"]
          }]
        }
        pools = {
          bulk = {
            datasets = {
              jdrive = {
                smb = {
                  share_name  = "jdrive"
                  comment     = "General file share"
                  valid_users = "@nas"
                }
              }
              timemachine = {
                smb = {
                  share_name            = "timemachine"
                  time_machine          = true
                  time_machine_max_size = "600G"
                }
              }
            }
          }
        }
      }
    }
  }
}

# --- Negative: Time Machine without a cap grows until the pool is full ---

run "time_machine_without_max_size_rejected" {
  command = plan

  variables {
    node_storage = {
      test-node = {
        pools = {
          bulk = {
            datasets = {
              timemachine = {
                smb = {
                  share_name   = "timemachine"
                  time_machine = true
                }
              }
            }
          }
        }
      }
    }
  }

  expect_failures = [
    var.node_storage,
  ]
}

# An empty string is not a cap. Guards that test only for "defined" accept it.
run "time_machine_with_empty_max_size_rejected" {
  command = plan

  variables {
    node_storage = {
      test-node = {
        pools = {
          bulk = {
            datasets = {
              timemachine = {
                smb = {
                  share_name            = "timemachine"
                  time_machine          = true
                  time_machine_max_size = ""
                }
              }
            }
          }
        }
      }
    }
  }

  expect_failures = [
    var.node_storage,
  ]
}

# --- Negative: duplicate share names shadow each other in smb.conf ---

run "duplicate_share_names_on_one_node_rejected" {
  command = plan

  variables {
    node_storage = {
      test-node = {
        pools = {
          bulk = {
            datasets = {
              first  = { smb = { share_name = "models" } }
              second = { smb = { share_name = "models" } }
            }
          }
        }
      }
    }
  }

  expect_failures = [
    var.node_storage,
  ]
}

# The same name on a DIFFERENT node is fine — the namespace is per-node, and a
# guard that rejected this would block the intended one-share-per-node layout.
run "same_share_name_on_different_nodes_accepted" {
  command = plan

  variables {
    node_storage = {
      node-a = {
        pools = { bulk = { datasets = { d = { smb = { share_name = "models" } } } } }
      }
      node-b = {
        pools = { bulk = { datasets = { d = { smb = { share_name = "models" } } } } }
      }
    }
  }
}

# --- Control: datasets with no SMB block at all are untouched ---

run "datasets_without_smb_unaffected" {
  command = plan

  variables {
    node_storage = {
      test-node = {
        pools = {
          bulk = {
            datasets = {
              plain = { quota = "1T" }
            }
          }
        }
      }
    }
  }
}

# --- valid_users must name groups, never accounts ---------------------------
#
# The negative case is the one that matters: Samba reads a bare word as a
# USERNAME, so a guard that accepts it would put a login name into both the
# desired state and the rendered smb.conf.

run "valid_users_naming_an_account_rejected" {
  command = plan

  variables {
    node_storage = {
      test-node = {
        pools = {
          bulk = {
            datasets = {
              jdrive = {
                smb = {
                  share_name  = "jdrive"
                  valid_users = "someuser"
                }
              }
            }
          }
        }
      }
    }
  }

  expect_failures = [var.node_storage]
}

run "valid_users_with_one_bad_entry_in_a_list_rejected" {
  command = plan

  variables {
    node_storage = {
      test-node = {
        pools = {
          bulk = {
            datasets = {
              jdrive = {
                smb = {
                  share_name  = "jdrive"
                  valid_users = "@nas, someuser"
                }
              }
            }
          }
        }
      }
    }
  }

  expect_failures = [var.node_storage]
}

run "valid_users_group_forms_accepted" {
  command = plan

  variables {
    node_storage = {
      test-node = {
        pools = {
          bulk = {
            datasets = {
              at_form   = { smb = { share_name = "a", valid_users = "@nas" } }
              plus_form = { smb = { share_name = "b", valid_users = "+nas" } }
              multi     = { smb = { share_name = "c", valid_users = "@nas, +staff" } }
              unset     = { smb = { share_name = "d" } }
            }
          }
        }
      }
    }
  }
}

# --- managed_users.secret_prefix must be unique within a node ---------------

run "duplicate_secret_prefix_on_one_node_rejected" {
  command = plan

  variables {
    node_storage = {
      test-node = {
        smb = {
          managed_users = [
            { secret_prefix = "smb_user" },
            { secret_prefix = "smb_user" },
          ]
        }
        pools = { bulk = { datasets = {} } }
      }
    }
  }

  expect_failures = [var.node_storage]
}

run "distinct_secret_prefixes_accepted" {
  command = plan

  variables {
    node_storage = {
      test-node = {
        smb = {
          managed_users = [
            { secret_prefix = "smb_service_account", unix_groups = ["nas"] },
            { secret_prefix = "smb_user", unix_groups = ["nas"] },
          ]
        }
        pools = { bulk = { datasets = {} } }
      }
    }
  }
}
