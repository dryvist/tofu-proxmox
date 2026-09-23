# Preserve every existing infrastructure address when the root configuration is
# wrapped with native RustFS/OpenBao inputs for Terrakube execution.
moved {
  from = module.storage
  to   = module.homelab.module.storage
}

moved {
  from = module.pools
  to   = module.homelab.module.pools
}

moved {
  from = module.vms
  to   = module.homelab.module.vms
}

moved {
  from = module.containers
  to   = module.homelab.module.containers
}

moved {
  from = module.splunk_vm
  to   = module.homelab.module.splunk_vm
}

moved {
  from = module.acme_certificates
  to   = module.homelab.module.acme_certificates
}

moved {
  from = module.rack_server_cluster
  to   = module.homelab.module.rack_server_cluster
}

moved {
  from = module.firewall
  to   = module.homelab.module.firewall
}

# The composition (providers, ephemeral credential fetches, the deployment
# decode, and the module.homelab call) moved one level down into
# modules/proxmox-root so it can be sourced as a module by another
# repository's own root (Vikunja 3492 — see modules/proxmox-root/main.tf for
# why). This is the same technique the migration above used: a `moved` block
# so every existing infrastructure address is preserved with no destroy or
# recreate, this time reparenting the whole module in one block rather than
# resource by resource.
moved {
  from = module.homelab
  to   = module.stack.module.homelab
}

# The former AWS inventory object remains available during the migration soak.
# Terrakube creates the replacement in RustFS; retire the orphaned AWS object
# separately only after every Ansible consumer has proven the native path.
removed {
  from = aws_s3_object.ansible_inventory

  lifecycle {
    destroy = false
  }
}
