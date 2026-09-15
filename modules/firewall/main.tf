terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.113"
    }
  }
}

# =============================================================================
# Cluster-Level Firewall (must be enabled for VM/container rules to work)
# =============================================================================

# Enable the datacenter/cluster-level firewall
# Without this, VM-level firewall rules are NOT applied
resource "proxmox_virtual_environment_cluster_firewall" "main" {
  enabled = true

  # Ebtables for layer 2 filtering (disabled - not needed for basic firewall)
  ebtables = false

  # Default policies at cluster level
  # IMPORTANT: Use ACCEPT here - VM-level policies (DROP) handle the actual filtering
  # The cluster firewall is only for enabling the firewall subsystem, not for filtering VM traffic
  input_policy  = "ACCEPT"
  output_policy = "ACCEPT"

  # Log rate limiting to prevent log flooding
  log_ratelimit {
    enabled = true
    burst   = 10
    rate    = "5/second"
  }
}
