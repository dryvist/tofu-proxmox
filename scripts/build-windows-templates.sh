#!/usr/bin/env bash
# Builds the Windows VDI templates defined in packer/windows/. Reads every
# secret from OpenBao at call time and exports it as PKR_VAR_*, so nothing lands
# on disk and no -var-file is needed (the sibling packer/ directory's
# variables.pkrvars.hcl has never existed in history, which is why its own build
# script cannot run).
#
# Usage: ./scripts/build-windows-templates.sh <init|validate|build> [win10|win11|win25]
#
# Run this from the iac-platform guest, not a workstation: Packer needs both the
# Proxmox API and a WinRM connection to the VM it is building, and macOS Local
# Network privacy denies the latter in a way that presents as "no route to host".
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKER_DIR="$REPO_ROOT/packer/windows"
cd "$PACKER_DIR"

OPENBAO_PACKER_PATH="${OPENBAO_PACKER_PATH:-secret/infrastructure/proxmox-packer}"
OPENBAO_WINDOWS_PATH="${OPENBAO_WINDOWS_PATH:-secret/platform/windows-vdi/win11-admin}"

# Packer is in no devShell in this workspace - the tofu shell does not carry it
# and the image-building shell the old docs referenced no longer exists. Pull it
# from nixpkgs at call time rather than pretending a shell provides it.
PACKER=(nix shell nixpkgs#packer --command packer)

log() { printf '\033[0;32m[INFO]\033[0m %s\n' "$1"; }
fail() {
  printf '\033[0;31m[ERROR]\033[0m %s\n' "$1" >&2
  exit 1
}

command -v bao >/dev/null 2>&1 || fail "bao not found (needed to read OpenBao)"
command -v nix >/dev/null 2>&1 || fail "nix not found (needed to provide packer)"

# Export a value without it ever appearing in argv - `export VAR=$(...)` is
# visible to any local user via ps for the lifetime of the subshell.
export_secret() {
  local var="$1" path="$2" field="$3" value
  value="$(bao kv get -field="$field" "$path" 2>/dev/null || true)"
  [[ -n $value ]] || fail "missing field '$field' at $path"
  export "PKR_VAR_${var}=${value}"
}

load_secrets() {
  log "reading Proxmox credentials from $OPENBAO_PACKER_PATH"
  local var
  for var in PROXMOX_VE_ENDPOINT PKR_PVE_USERNAME PROXMOX_TOKEN PROXMOX_VE_NODE; do
    export_secret "$var" "$OPENBAO_PACKER_PATH" "$var"
  done

  # Optional - absence is not an error, unlike the four above.
  local insecure
  insecure="$(bao kv get -field=PROXMOX_VE_INSECURE "$OPENBAO_PACKER_PATH" 2>/dev/null || true)"
  [[ -n $insecure ]] && export "PKR_VAR_PROXMOX_VE_INSECURE=${insecure}"

  log "reading the Windows Administrator credential from $OPENBAO_WINDOWS_PATH"
  export_secret WINDOWS_ADMIN_PASSWORD "$OPENBAO_WINDOWS_PATH" password
}

# Guard the one mistake this layout exists to prevent: `packer build .` builds
# every source it finds, so an unqualified build would make all three Windows
# templates at once.
resolve_only() {
  local image="${1:-}"
  case "$image" in
    win10 | win11 | win25) printf -- '-only=windows-templates.proxmox-iso.%s' "$image" ;;
    "") fail "specify an image: win10, win11 or win25" ;;
    *) fail "unknown image '$image' (expected win10, win11 or win25)" ;;
  esac
}

case "${1:-}" in
  init)
    log "initialising Packer plugins"
    "${PACKER[@]}" init .
    ;;
  validate)
    load_secrets
    log "validating configuration"
    "${PACKER[@]}" validate .
    log "configuration is valid"
    ;;
  build)
    load_secrets
    only="$(resolve_only "${2:-}")"
    log "building ${2} template (this installs Windows unattended; expect 30-60 min)"
    "${PACKER[@]}" build "$only" .
    ;;
  *)
    cat <<'USAGE'
Usage: ./scripts/build-windows-templates.sh <command> [image]

Commands:
  init                  Install the Proxmox plugin
  validate              Check the configuration against OpenBao-sourced variables
  build <image>         Build one template; image is win10, win11 or win25

Environment:
  OPENBAO_PACKER_PATH   Proxmox API credentials  (default secret/infrastructure/proxmox-packer)
  OPENBAO_WINDOWS_PATH  Windows Administrator    (default secret/platform/windows-vdi/win11-admin)

Templates are node-local: build on the node the VDI guests are cloned onto.
USAGE
    exit 1
    ;;
esac

log "done"
