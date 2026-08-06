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

# Windows Setup rejects a malformed answer file outright and reports it only on
# the VM's console, which is invisible to an unattended pipeline - it looks like
# the install simply never progressed. Parse before shipping. (A missing
# xmlns:wcm declaration shipped undetected exactly this way.)
#
# The DOCTYPE refusal is what makes the stdlib parser safe to use here: XXE and
# billion-laughs both need entity declarations, which need a DOCTYPE, and an
# answer file never legitimately has one. That avoids installing defusedxml on a
# hypervisor purely for a well-formedness check.
XML_CHECK='
import re, sys, xml.etree.ElementTree as ET
raw = open(sys.argv[1], "rb").read()
if re.search(rb"<!DOCTYPE", raw, re.I):
    sys.exit("refusing to parse: answer file must not declare a DOCTYPE")
ET.fromstring(raw)
'
python3 -c "$XML_CHECK" "$TEMPLATE"

ssh -i ~/.ssh/id_rsa_pve "root@${PVE_HOST}" "mkdir -p /tmp/win11-answer-build"
# perl (not sed): the replacement reads WIN11_ADMIN_PASSWORD via $ENV{} inside
# the script text, so the password never appears in this process's argv (a
# `sed "s/.../${WIN11_ADMIN_PASSWORD}/"` argument is visible to any local user
# via `ps`). The value is XML-escaped on the way in - an unescaped & or < in a
# generated password would corrupt the answer file with the same silent
# console-only failure.
perl -pe '
  BEGIN {
    $p = $ENV{WIN11_ADMIN_PASSWORD};
    $p =~ s/&/&amp;/g; $p =~ s/</&lt;/g; $p =~ s/>/&gt;/g;
    $p =~ s/"/&quot;/g; $p =~ s/'"'"'/&apos;/g;
  }
  s/__ADMIN_PASSWORD__/$p/g;
' "$TEMPLATE" \
  | ssh -i ~/.ssh/id_rsa_pve "root@${PVE_HOST}" "cat > /tmp/win11-answer-build/autounattend.xml"

# Re-parse the rendered file on the node: escaping bugs only surface post-
# substitution. The checker goes over stdin (python3 - <file>) so its own quoting
# survives the ssh hop. Only the parser's verdict crosses back, never the file
# content - a parse error must not echo a line containing the password.
printf '%s' "$XML_CHECK" \
  | ssh -i ~/.ssh/id_rsa_pve "root@${PVE_HOST}" \
      "python3 - /tmp/win11-answer-build/autounattend.xml >/dev/null 2>&1 \
       && echo 'rendered answer file parses OK' \
       || { echo 'rendered answer file FAILED to parse' >&2; exit 1; }"

ssh -i ~/.ssh/id_rsa_pve "root@${PVE_HOST}" bash -s <<REMOTE
set -euo pipefail
which genisoimage >/dev/null 2>&1 || apt-get install -y genisoimage
genisoimage -J -r -o "${PVE_ISO_DIR}/win11-vdi-answer.iso" /tmp/win11-answer-build/autounattend.xml
rm -rf /tmp/win11-answer-build
ls -la "${PVE_ISO_DIR}/win11-vdi-answer.iso"
REMOTE

echo "win11-vdi-answer.iso placed on ${PVE_HOST}:${PVE_ISO_DIR}"
