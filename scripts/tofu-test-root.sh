#!/usr/bin/env bash
# Run the root deployment-source checks: ./scripts/tofu-test-root.sh
#
# The RustFS-fallback scenario (no local deployment.json — the state every
# ordinary checkout is in, since the file is gitignored) has a real,
# automated `tofu test`: tests/deployment_source_s3_fallback.tftest.hcl.
#
# The local-file scenario (a homelab-live checkout dropping its own
# deployment.json into this root) does NOT have a `.tftest.hcl` sibling.
# Two independent, reproducible OpenTofu v1.12.5 `tofu test` limitations
# block one, confirmed by hand rather than assumed:
#
#   1. A mocked `ephemeral` resource's data is only available to the FIRST
#      consumer that reads it (main.tf's own `provider "proxmox"` block).
#      A second reference to the SAME mocked ephemeral instance — here,
#      module.homelab's call-site arguments reading
#      ephemeral.vault_kv_secret_v2.proxmox.data.PROXMOX_VE_HOSTNAME /
#      .PROXMOX_SSH_PRIVATE_KEY a second time — comes back "Missing map
#      element", even though the first read of the same key succeeded.
#      Tracks opentofu/opentofu#4251 (ephemeral-resource test support).
#   2. plan_options.target does not prune reliably when the target set's
#      only real object is behind a `count = fileexists(...) ? 0 : 1`
#      data source whose count evaluates to 0 (this branch) and that data
#      source is referenced from a ternary elsewhere in the config
#      (deployment_source.tf's `local.deployment_body`/`desired_state_etag`).
#      Confirmed by a controlled A/B: the identical target, mocks, and
#      assert pass cleanly when that data source's count is 1 (the
#      S3-fallback scenario) and pull in the WHOLE root — including
#      imports.tf's six unconditional `import` blocks, which name real,
#      unrelated container keys — when its count is 0.
#
# Limitation 2 rules out scoping a plan down to just the local-file branch
# the way the S3-fallback test does; limitation 1 then blocks a full,
# unscoped plan from ever reaching module.homelab's call site. Neither is
# an HCL mistake in this repository to fix.
#
# `tofu validate` sidesteps both: it needs no provider configured (so the
# ephemeral double-read in #1 never happens) and evaluates every
# constant-foldable expression, INCLUDING the output.deployment_validated
# preconditions this file shares with the S3 path (confirmed: deliberately
# breaking tests/fixtures/deployment.json.example here reproduces the precondition's
# own error_message, not just a generic type error). That is what this
# script runs for the local-file branch, as the closest automated
# equivalent available on this OpenTofu version.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
cd "${PROJECT_ROOT}"

FIXTURE="tests/fixtures/deployment.json.example"
LOCAL_COPY="deployment.json"

cleanup() {
  rm -f "${LOCAL_COPY}"
}
trap cleanup EXIT

echo "== deployment source: RustFS fallback (no local file) — tofu test"
rm -f "${LOCAL_COPY}"
tofu test -filter=tests/deployment_source_s3_fallback.tftest.hcl -no-color

echo "== deployment source: local file present — tofu validate"
cp "${FIXTURE}" "${LOCAL_COPY}"
tofu validate -no-color
rm -f "${LOCAL_COPY}"

echo "root deployment-source checks: both scenarios passed"
