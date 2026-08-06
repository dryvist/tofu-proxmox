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
PACKER_IMAGE="${PACKER_IMAGE:-hashicorp/packer:latest}"

# Every variable the configuration declares, unprefixed. Drives both the OpenBao
# reads and the set forwarded into the container, so the two cannot drift.
PKR_VARS=(
  PROXMOX_VE_ENDPOINT
  PKR_PVE_USERNAME
  PROXMOX_TOKEN
  PROXMOX_VE_NODE
  PROXMOX_VE_INSECURE
  WINDOWS_ADMIN_PASSWORD
)

log() { printf '\033[0;32m[INFO]\033[0m %s\n' "$1"; }
fail() {
  printf '\033[0;31m[ERROR]\033[0m %s\n' "$1" >&2
  exit 1
}

# Packer is in no devShell in this workspace, and the two hosts that could run
# this carry different tooling: a workstation has nix but no docker, while the
# LAN execution guest has docker but neither nix nor a packer binary. Resolve
# whatever is actually present instead of assuming one of them.
#
# nix needs NIXPKGS_ALLOW_UNFREE because HashiCorp relicensed Packer to BSL,
# which nixpkgs classifies as unfree and refuses to evaluate. That acknowledges
# a licence rather than suppressing a check - unlike Terraform to OpenTofu,
# Packer has no OSS fork to switch to. It needs --impure because the variable is
# read from the ambient environment.
#
# The docker form uses host networking because the builder must reach both the
# Proxmox API and WinRM on the VM it is creating, and persists the plugin cache
# so `init` is not repeated on every call.
resolve_packer() {
  if command -v packer >/dev/null 2>&1; then
    PACKER=(packer)
  elif command -v nix >/dev/null 2>&1; then
    PACKER=(env NIXPKGS_ALLOW_UNFREE=1 nix shell --impure nixpkgs#packer --command packer)
  elif command -v docker >/dev/null 2>&1; then
    mkdir -p "$HOME/.config/packer"
    PACKER=(docker run --rm --network host
      -v "$PACKER_DIR:/work" -w /work
      -v "$HOME/.config/packer:/root/.config/packer")
    # `-e NAME` with no value forwards the value from this shell, so no secret
    # is written to a file or exposed in the container's argv.
    local var
    for var in "${PKR_VARS[@]}"; do
      PACKER+=(-e "PKR_VAR_$var")
    done
    PACKER+=("$PACKER_IMAGE")
  else
    fail "no packer, nix or docker found - cannot obtain a packer binary"
  fi
}

# Reads OpenBao over its HTTP API rather than the bao CLI, which is absent on
# the execution guest. Authenticates with BAO_TOKEN when set, otherwise logs in
# with the AppRole pair the execution-host docs already require operators to
# export.
bao_login() {
  [[ -n ${BAO_ADDR:-} ]] || fail "BAO_ADDR is unset"
  if [[ -n ${BAO_TOKEN:-} ]]; then
    return
  fi
  [[ -n ${OPENBAO_APPROLE_PACKER_ROLE_ID:-} && -n ${OPENBAO_APPROLE_PACKER_SECRET_ID:-} ]] ||
    fail "set BAO_TOKEN, or OPENBAO_APPROLE_PACKER_ROLE_ID and OPENBAO_APPROLE_PACKER_SECRET_ID"
  BAO_TOKEN="$(
    jq -nc --arg r "$OPENBAO_APPROLE_PACKER_ROLE_ID" --arg s "$OPENBAO_APPROLE_PACKER_SECRET_ID" \
      '{role_id: $r, secret_id: $s}' |
      curl -sS --fail-with-body -X POST -d @- "$BAO_ADDR/v1/auth/approle/login" |
      jq -r '.auth.client_token // empty'
  )" || fail "AppRole login to $BAO_ADDR failed"
  [[ -n $BAO_TOKEN ]] || fail "AppRole login returned no token"
  export BAO_TOKEN
}

# Export a value without it ever appearing in argv - `export VAR=$(...)` is
# visible to any local user via ps for the lifetime of the subshell.
export_secret() {
  local var="$1" path="$2" field="$3"
  local mount="${path%%/*}" rest="${path#*/}" value
  value="$(
    curl -sS -H "X-Vault-Token: $BAO_TOKEN" "$BAO_ADDR/v1/$mount/data/$rest" |
      jq -r --arg f "$field" '.data.data[$f] // empty'
  )"
  [[ -n $value ]] || fail "missing field '$field' at $path"
  export "PKR_VAR_${var}=${value}"
}

load_secrets() {
  bao_login
  log "reading Proxmox credentials from $OPENBAO_PACKER_PATH"
  local var
  for var in PROXMOX_VE_ENDPOINT PKR_PVE_USERNAME PROXMOX_TOKEN PROXMOX_VE_NODE; do
    export_secret "$var" "$OPENBAO_PACKER_PATH" "$var"
  done

  # Optional - absence is not an error, unlike the four above.
  PKR_VAR_PROXMOX_VE_INSECURE="$(
    curl -sS -H "X-Vault-Token: $BAO_TOKEN" \
      "$BAO_ADDR/v1/${OPENBAO_PACKER_PATH%%/*}/data/${OPENBAO_PACKER_PATH#*/}" |
      jq -r '.data.data.PROXMOX_VE_INSECURE // empty'
  )"
  [[ -n $PKR_VAR_PROXMOX_VE_INSECURE ]] && export PKR_VAR_PROXMOX_VE_INSECURE || true

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

for tool in curl jq; do
  command -v "$tool" >/dev/null 2>&1 || fail "$tool not found (needed to read OpenBao)"
done
resolve_packer

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
  BAO_ADDR              OpenBao address (required)
  BAO_TOKEN             OpenBao token, or set the AppRole pair below instead
  OPENBAO_APPROLE_PACKER_ROLE_ID
  OPENBAO_APPROLE_PACKER_SECRET_ID
  OPENBAO_PACKER_PATH   Proxmox API credentials  (default secret/infrastructure/proxmox-packer)
  OPENBAO_WINDOWS_PATH  Windows Administrator    (default secret/platform/windows-vdi/win11-admin)
  PACKER_IMAGE          Image used when only docker is available (default hashicorp/packer:latest)

Packer is taken from PATH, else nix, else docker - whichever the host has.

Templates are node-local: build on the node the VDI guests are cloned onto.
USAGE
    exit 1
    ;;
esac

log "done"
