# Container environment_variables reach the container resource unchanged.
mock_provider "proxmox" {}

variables {
  domain            = "example.test"
  environment       = "test"
  default_datastore = "local-zfs"

  containers = {
    youtrack = {
      vm_id            = 605080
      node_name        = "proxmox-1"
      hostname         = "youtrack"
      template_file_id = "local:vztmpl/youtrack-oci.tar"
      os_type          = "unmanaged"
      environment_variables = {
        JAVA_TOOL_OPTIONS = "-Xmx3g -XX:MaxMetaspaceSize=350m"
      }
    }
    plain = {
      vm_id            = 605081
      node_name        = "proxmox-1"
      hostname         = "plain"
      template_file_id = "local:vztmpl/example.tar.zst"
    }
  }
}

run "environment_variables_reach_the_container_resource" {
  command = plan

  assert {
    condition     = proxmox_virtual_environment_container.containers["youtrack"].environment_variables["JAVA_TOOL_OPTIONS"] == "-Xmx3g -XX:MaxMetaspaceSize=350m"
    error_message = "youtrack must carry JAVA_TOOL_OPTIONS in environment_variables"
  }

  assert {
    condition     = proxmox_virtual_environment_container.containers["plain"].environment_variables == null
    error_message = "a container that sets no environment_variables must leave the attribute unset"
  }
}
