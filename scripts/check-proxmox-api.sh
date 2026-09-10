#!/usr/bin/env bash
# Test Proxmox API health before running Terraform operations
# Run this script before tofu plan/apply to verify API connectivity
set -euo pipefail

echo "=== Proxmox API Health Check ==="
echo "Endpoint: ${PROXMOX_VE_ENDPOINT:-<not set>}"
echo ""

if [[ -z "${PROXMOX_VE_ENDPOINT:-}" ]]; then
  echo "ERROR: PROXMOX_VE_ENDPOINT is not set"
  echo "Run this check from an OpenBao-authenticated operator session."
  exit 1
fi

if [[ -z "${PROXMOX_VE_API_TOKEN:-}" ]]; then
  echo "ERROR: PROXMOX_VE_API_TOKEN is not set"
  echo "Run this check from an OpenBao-authenticated operator session."
  exit 1
fi

# No default. A literal fallback here does not fail -- it silently checks a
# different node than the one intended and reports that node's health as the
# answer, which is a wrong result presented as a working check.
if [[ -z "${PROXMOX_VE_NODE:-}" ]]; then
  echo "ERROR: PROXMOX_VE_NODE is not set"
  echo "Run this check from an OpenBao-authenticated operator session."
  exit 1
fi

# Optional: Use a custom CA certificate for TLS validation if provided.
# If PROXMOX_VE_CACERT is not set, curl will use the system trust store.
CURL_TLS_OPTS=()
if [[ -n "${PROXMOX_VE_CACERT:-}" ]]; then
  CURL_TLS_OPTS=(--cacert "${PROXMOX_VE_CACERT}")
fi

# Test 1: Version endpoint (fastest)
echo "1. Version check (should be <1s):"
time curl "${CURL_TLS_OPTS[@]}" -s -m 10 \
  -X GET "${PROXMOX_VE_ENDPOINT}/api2/json/version" \
  -H "Authorization: PVEAPIToken=${PROXMOX_VE_API_TOKEN}" | jq -r '.data.version'

# Test 2: Node status
echo ""
echo "2. Node status (shows load):"
time curl "${CURL_TLS_OPTS[@]}" -s -m 10 \
  -X GET "${PROXMOX_VE_ENDPOINT}/api2/json/nodes/${PROXMOX_VE_NODE}/status" \
  -H "Authorization: PVEAPIToken=${PROXMOX_VE_API_TOKEN}" | jq '{cpu: .data.cpu, memory: .data.memory}'

# Test 3: List VMs (exercises state refresh path)
echo ""
echo "3. List VMs (state refresh test):"
time curl "${CURL_TLS_OPTS[@]}" -s -m 15 \
  -X GET "${PROXMOX_VE_ENDPOINT}/api2/json/nodes/${PROXMOX_VE_NODE}/qemu" \
  -H "Authorization: PVEAPIToken=${PROXMOX_VE_API_TOKEN}" | jq '.data | length' | xargs echo "VMs found:"

# Test 4: List containers
echo ""
echo "4. List containers:"
time curl "${CURL_TLS_OPTS[@]}" -s -m 15 \
  -X GET "${PROXMOX_VE_ENDPOINT}/api2/json/nodes/${PROXMOX_VE_NODE}/lxc" \
  -H "Authorization: PVEAPIToken=${PROXMOX_VE_API_TOKEN}" | jq '.data | length' | xargs echo "Containers found:"

echo ""
echo "=== Health Check Complete ==="
echo "If any test takes >5s, consider waiting before running Terraform."
echo "If any test fails, check Proxmox host resources and network connectivity."
