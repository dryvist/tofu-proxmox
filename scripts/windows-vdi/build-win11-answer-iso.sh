#!/usr/bin/env bash
# Builds win11-vdi's autounattend answer-file ISO directly on pve540 (where it's
# needed) and places it in local ISO storage alongside the hand-placed Windows
# ISOs. Never writes the Administrator password to a file on this machine.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE="$REPO_ROOT/windows-vdi/win11-autounattend.xml.template"
PVE_HOST="pve540.jacobpevans.com"
PVE_ISO_DIR="/var/lib/vz/template/iso"

: "${WIN11_ADMIN_PASSWORD:?set WIN11_ADMIN_PASSWORD from OpenBao before running}"

ssh -i ~/.ssh/id_rsa_pve "root@${PVE_HOST}" "mkdir -p /tmp/win11-answer-build"
# perl (not sed): the replacement reads WIN11_ADMIN_PASSWORD via $ENV{} inside
# the script text, so the password never appears in this process's argv (a
# `sed "s/.../${WIN11_ADMIN_PASSWORD}/"` argument is visible to any local user
# via `ps`).
perl -pe 's/__ADMIN_PASSWORD__/$ENV{WIN11_ADMIN_PASSWORD}/g' "$TEMPLATE" \
  | ssh -i ~/.ssh/id_rsa_pve "root@${PVE_HOST}" "cat > /tmp/win11-answer-build/autounattend.xml"

ssh -i ~/.ssh/id_rsa_pve "root@${PVE_HOST}" bash -s <<REMOTE
set -euo pipefail
which genisoimage >/dev/null 2>&1 || apt-get install -y genisoimage
genisoimage -J -r -o "${PVE_ISO_DIR}/win11-vdi-answer.iso" /tmp/win11-answer-build/autounattend.xml
rm -rf /tmp/win11-answer-build
ls -la "${PVE_ISO_DIR}/win11-vdi-answer.iso"
REMOTE

echo "win11-vdi-answer.iso placed on ${PVE_HOST}:${PVE_ISO_DIR}"
