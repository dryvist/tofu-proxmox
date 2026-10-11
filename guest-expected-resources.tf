# Every guest SHOULD declare expected_resources (avg and peak); see
# docs/CONTAINER_SCHEMA.md. deployment.schema.json owns field names and
# non-negative values; this file adds only what the schema cannot express.
# A failed check only warns, so a plan still completes.
#
# The SHOULD-to-MUST flip turns the missing-profile check into a precondition.
locals {
  guest_expected_resources = merge(
    { for name, guest in local.containers : "containers.${name}" => try(guest.expected_resources, null) },
    { for name, guest in try(local.deployment.vms, {}) : "vms.${name}" => try(guest.expected_resources, null) },
  )

  guest_expected_resources_missing = sort([
    for key, profile in local.guest_expected_resources : key
    if try(profile.avg, null) == null || try(profile.peak, null) == null
  ])

  guest_expected_resources_peak_below_avg = sort(flatten([
    for key, profile in local.guest_expected_resources : [
      for field, peak in coalesce(try(profile.peak, null), {}) : "${key}.${field}"
      if try(peak < profile.avg[field], false)
    ]
  ]))
}

check "guest_expected_resources" {
  assert {
    condition     = length(local.guest_expected_resources_missing) == 0
    error_message = "Guests missing expected_resources avg and peak: ${join(", ", local.guest_expected_resources_missing)}."
  }

  assert {
    condition     = length(local.guest_expected_resources_peak_below_avg) == 0
    error_message = "expected_resources peak below avg: ${join(", ", local.guest_expected_resources_peak_below_avg)}."
  }
}
