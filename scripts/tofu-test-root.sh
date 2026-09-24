#!/usr/bin/env bash
# Validate the root with a local deployment.json present:
# ./scripts/tofu-test-root.sh
#
# `tofu test` cannot cover this scenario on the pinned OpenTofu version, so
# this runs `tofu validate` instead — it still evaluates deployment_source.tf's
# output preconditions against the fixture, since they need no provider.
# `tofu test -no-color` (the S3-fallback path) already runs as its own CI
# step and is not repeated here.
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

cp "${FIXTURE}" "${LOCAL_COPY}"
tofu validate -no-color
echo "root deployment-source check (local file): passed"
