# network_interfaces[].host_managed reaches the container's NIC unchanged.
mock_provider "proxmox" {}

variables {
  domain            = "example.test"
  environment       = "test"
  default_datastore = "local-zfs"

  containers = {
    oci = {
      vm_id              = 605080
      node_name          = "proxmox-1"
      hostname           = "oci"
      template_file_id   = "local:vztmpl/youtrack-oci.tar"
      os_type            = "unmanaged"
      network_interfaces = [{ name = "eth0", bridge = "vmbr0", firewall = true, host_managed = true }]
    }
    plain = {
      vm_id            = 605081
      node_name        = "proxmox-1"
      hostname         = "plain"
      template_file_id = "local:vztmpl/example.tar.zst"
    }
  }
}

run "host_managed_reaches_the_nic" {
  command = plan

  assert {
    condition     = proxmox_virtual_environment_container.containers["oci"].network_interface[0].host_managed == true
    error_message = "an interface that sets host_managed must carry it to the container NIC"
  }

  assert {
    condition     = proxmox_virtual_environment_container.containers["plain"].network_interface[0].host_managed == null
    error_message = "an interface that leaves host_managed unset must not send it"
  }
}
