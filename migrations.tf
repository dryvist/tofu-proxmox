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

# The former AWS inventory object remains available during the migration soak.
# Terrakube creates the replacement in RustFS; retire the orphaned AWS object
# separately only after every Ansible consumer has proven the native path.
removed {
  from = aws_s3_object.ansible_inventory

  lifecycle {
    destroy = false
  }
}

# GPU guests renamed to the llm-<generation>-<gddr>-<vram>GB-<role> pattern: the
# state addresses follow the new map key, so no container is replaced.

moved {
  from = module.homelab.module.containers[0].proxmox_virtual_environment_container.containers["llm-ada-lovelace-6X-16G"]
  to   = module.homelab.module.containers[0].proxmox_virtual_environment_container.containers["llm-ada-lovelace-6X-16GB-embed"]
}

moved {
  from = module.homelab.module.firewall.proxmox_virtual_environment_firewall_options.llm_fast_container["llm-ada-lovelace-6X-16G"]
  to   = module.homelab.module.firewall.proxmox_virtual_environment_firewall_options.llm_fast_container["llm-ada-lovelace-6X-16GB-embed"]
}

moved {
  from = module.homelab.module.firewall.proxmox_virtual_environment_firewall_rules.llm_fast_container["llm-ada-lovelace-6X-16G"]
  to   = module.homelab.module.firewall.proxmox_virtual_environment_firewall_rules.llm_fast_container["llm-ada-lovelace-6X-16GB-embed"]
}

moved {
  from = module.homelab.module.containers[0].proxmox_virtual_environment_container.containers["llm-6000"]
  to   = module.homelab.module.containers[0].proxmox_virtual_environment_container.containers["llm-blackwell-7-96GB-medium"]
}

moved {
  from = module.homelab.module.firewall.proxmox_virtual_environment_firewall_options.llm_fast_container["llm-6000"]
  to   = module.homelab.module.firewall.proxmox_virtual_environment_firewall_options.llm_fast_container["llm-blackwell-7-96GB-medium"]
}

moved {
  from = module.homelab.module.firewall.proxmox_virtual_environment_firewall_rules.llm_fast_container["llm-6000"]
  to   = module.homelab.module.firewall.proxmox_virtual_environment_firewall_rules.llm_fast_container["llm-blackwell-7-96GB-medium"]
}
