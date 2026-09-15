terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.113"
    }
  }
}

resource "proxmox_virtual_environment_pool" "pools" {
  for_each = var.pools

  pool_id = each.key
  comment = each.value.comment != null ? each.value.comment : "TF Pool ${title(each.key)} - ${var.environment}"

  lifecycle {
    create_before_destroy = true
  }
}
