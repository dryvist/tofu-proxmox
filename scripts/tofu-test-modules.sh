#!/usr/bin/env bash
# Run every module test suite in this repo: ./scripts/tofu-test-modules.sh
#
# `tofu test` does not recurse into modules/*/tests, so the root invocation
# reports success having run nothing from the modules. Each suite has to be
# entered on its own.
#
# The set of suites is DERIVED from which modules carry a tests/ directory,
# never hand-listed. A hand-listed set silently omits the next module that
# gains tests, and an omitted suite is indistinguishable from a passing one.
#
# Assertions are counted and printed, and a run that executes zero of them
# fails. A suite that stops running otherwise reports success by doing nothing.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
cd "${PROJECT_ROOT}"

shopt -s nullglob
suites=(modules/*/tests)
shopt -u nullglob

if [ ${#suites[@]} -eq 0 ]; then
  echo "ERROR: no module test suites found under modules/*/tests" >&2
  exit 1
fi

total=0
for suite in "${suites[@]}"; do
  module="${suite%/tests}"
  count=$(grep -rho 'assert {' "${suite}" --include='*.tftest.hcl' | wc -l | tr -d ' ')
  echo "== ${module} (${count} assertions)"
  tofu -chdir="${module}" init -backend=false -no-color
  tofu -chdir="${module}" test -no-color
  total=$((total + count))
done

echo "module suites: ${#suites[@]}, assertions: ${total}"

if [ "${total}" -eq 0 ]; then
  echo "ERROR: module suites ran zero assertions" >&2
  exit 1
fi
