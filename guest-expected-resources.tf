# Every guest SHOULD declare expected_resources (avg and peak); see
# docs/CONTAINER_SCHEMA.md. A failed check only warns, so a plan still
# completes. It sits in the root, on the decoded desired state, so module
# tests with minimal fixtures are not affected.
#
# The SHOULD-to-MUST flip moves this assertion into a variable validation.
locals {
  guest_expected_resources_missing = sort(concat(
    [
      for name, guest in local.containers : "containers.${name}"
      if try(guest.expected_resources.avg, null) == null || try(guest.expected_resources.peak, null) == null
    ],
    [
      for name, guest in try(local.deployment.vms, {}) : "vms.${name}"
      if try(guest.expected_resources.avg, null) == null || try(guest.expected_resources.peak, null) == null
    ],
  ))
}

check "guest_expected_resources" {
  assert {
    condition     = length(local.guest_expected_resources_missing) == 0
    error_message = "Guests missing expected_resources avg and peak: ${join(", ", local.guest_expected_resources_missing)}."
  }
}
