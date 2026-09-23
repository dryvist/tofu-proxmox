variable "acme_accounts" {
  description = "ACME account configurations for Let's Encrypt certificate management"
  type = map(object({
    email     = string # Email address for Let's Encrypt notifications
    directory = string # ACME directory URL (production or staging)
    tos       = string # Terms of Service URL - setting this indicates agreement
  }))
  default = {}

  validation {
    condition = alltrue([
      for k, v in var.acme_accounts :
      can(regex("^[^@]+@[^@]+\\.[^@]+$", v.email))
    ])
    error_message = "Each email must be a valid email address."
  }

  validation {
    condition = alltrue([
      for k, v in var.acme_accounts :
      can(regex(
        "^(https://acme-v02\\.api\\.letsencrypt\\.org/directory|https://acme-staging-v02\\.api\\.letsencrypt\\.org/directory)$",
        v.directory
      ))
    ])
    error_message = "Each directory must be an HTTPS URL pointing to the Let's Encrypt ACME v2 production or staging directory."
  }
}

variable "dns_plugins" {
  description = "DNS challenge plugins for ACME validation (e.g., AWS Route53)"
  type = map(object({
    plugin_type = string      # API plugin name (e.g., "route53")
    data        = map(string) # DNS plugin data as key=value pairs (e.g., AWS credentials)
  }))
  default = {}

  # Note: Not marked sensitive here to allow for_each, but outputs are sensitive
}

variable "acme_certificates" {
  description = <<-EOT
    ACME certificates to provision and manage. Each entry maps to a single
    proxmox_acme_certificate resource per node, covering one primary domain
    plus optional SANs. After issuance, the cert (combined PEM bundle and/or
    split cert+key) can be delivered to LXCs or VMs via the module's
    null_resource provisioner.

    See README.md for the full schema and import procedure.
  EOT
  type = map(object({
    node_name     = string                     # Proxmox node name (e.g., "proxmox-1")
    domain        = string                     # Primary domain (CN)
    account_id    = string                     # ACME account name (key in var.acme_accounts)
    dns_plugin_id = string                     # DNS plugin name (key in var.dns_plugins)
    sans          = optional(list(string), []) # Additional SANs (each uses dns_plugin_id)
    destinations = optional(list(object({
      kind        = string           # "lxc" or "vm"
      target_id   = number           # vm_id of the LXC or VM
      target_ip   = optional(string) # required when kind = "vm"
      bundle_path = optional(string) # combined cert+key PEM
      cert_path   = optional(string) # separate cert+chain PEM
      key_path    = optional(string) # separate private key
      mode        = optional(string, "0600")
      owner       = optional(string, "root")
      group       = optional(string, "root")
      reload_cmd  = optional(string, "") # ran on target after delivery
    })), [])
  }))
  default = {}
}

variable "proxmox_ssh_host" {
  description = "Hostname/IP for SSH access to the Proxmox node. Used by the cert-delivery null_resource provisioner."
  type        = string
  default     = ""
  ephemeral   = true
}

variable "proxmox_user" {
  description = "The Proxmox login user for SSH and API auth (e.g., \"root\"), no realm"
  type        = string
}

variable "proxmox_ssh_private_key" {
  description = "Ephemeral SSH private key content for connecting to the Proxmox node."
  type        = string
  sensitive   = true
  ephemeral   = true
}

variable "environment" {
  description = "Environment name for tagging and organization"
  type        = string
  default     = "homelab"
}
