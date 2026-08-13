#!/bin/bash
# GTDataworks Portlock — add the public apt repository.
#
#   curl -fsSL https://gtdataworks.com/portlock/install-apt.sh | bash
#   # forgot sudo? goat mode re-runs elevated for you.
#
# Or:  sudo bash install-apt.sh
#
# Signed repository metadata is mandatory. There is no trusted=yes path.
set -euo pipefail

REPO_URL="${PORTLOCK_APT_URL:-https://cwwjacobs.github.io/gtdataworks-portlock}"
# Script location for re-fetch under sudo (curl | bash)
INSTALL_URL="${PORTLOCK_INSTALL_URL:-https://gtdataworks.com/portlock/install-apt.sh}"
LIST="/etc/apt/sources.list.d/gtdataworks-portlock.list"
KEYRING="/usr/share/keyrings/gtdataworks-portlock.gpg"
CODENAME="stable"

# Pinned expected fingerprint of the Portlock APT repository signing key.
# Install fails closed if KEY.gpg does not match this 40-hex value.
DEFAULT_PORTLOCK_APT_FINGERPRINT="BD744EF80F3F332FC5AE3A920F895B751BA12E22"
EXPECTED_FINGERPRINT="${PORTLOCK_APT_FINGERPRINT:-$DEFAULT_PORTLOCK_APT_FINGERPRINT}"

normalize_fpr() {
  local f="${1:-}"
  f="${f// /}"
  f="${f//$'\t'/}"
  printf '%s' "${f^^}"
}

is_pinned_fingerprint() {
  local f
  f="$(normalize_fpr "$1")"
  [[ "$f" =~ ^[0-9A-F]{40}$ ]]
}

require_pinned_fingerprint() {
  if ! is_pinned_fingerprint "$EXPECTED_FINGERPRINT"; then
    echo "error: no authoritative apt signing fingerprint is pinned." >&2
    echo "       install cannot proceed until PORTLOCK_APT_FINGERPRINT is" >&2
    echo "       the real 40-hex-digit fingerprint of the repo signing key." >&2
    echo "       (current value is a placeholder or invalid)" >&2
    return 1
  fi
  EXPECTED_FINGERPRINT="$(normalize_fpr "$EXPECTED_FINGERPRINT")"
  return 0
}

require_gpg() {
  if ! command -v gpg >/dev/null 2>&1; then
    echo "error: gpg is required to verify the repository signing key" >&2
    return 1
  fi
}

fetch_and_verify_key() {
  # Download KEY.gpg to a temp file, verify the pinned fingerprint, write keyring.
  local dest="${1:-}"
  local workdir keyfile gnupghome fpr found
  [[ -n "$dest" ]] || return 1
  require_pinned_fingerprint
  require_gpg

  workdir="$(mktemp -d)"
  keyfile="$(mktemp "$workdir/KEY.XXXXXX")"
  gnupghome="$(mktemp -d "$workdir/gnupg.XXXXXX")"
  chmod 700 "$gnupghome"

  if ! curl --proto '=https' --tlsv1.2 -fsSL "$REPO_URL/KEY.gpg" -o "$keyfile"; then
    echo "error: failed to fetch ${REPO_URL}/KEY.gpg over HTTPS" >&2
    rm -rf "$workdir"
    return 1
  fi
  if [[ ! -s "$keyfile" ]]; then
    echo "error: ${REPO_URL}/KEY.gpg is missing or empty" >&2
    rm -rf "$workdir"
    return 1
  fi

  if ! gpg --homedir "$gnupghome" --batch --quiet --import "$keyfile" 2>/dev/null; then
    echo "error: KEY.gpg is not a valid OpenPGP key" >&2
    rm -rf "$workdir"
    return 1
  fi

  found=0
  while IFS= read -r fpr; do
    [[ -n "$fpr" ]] || continue
    if [[ "$(normalize_fpr "$fpr")" == "$EXPECTED_FINGERPRINT" ]]; then
      found=1
      break
    fi
  done < <(gpg --homedir "$gnupghome" --batch --with-colons --fingerprint \
            | awk -F: '/^fpr:/ {print $10}')

  if [[ "$found" -ne 1 ]]; then
    echo "error: KEY.gpg fingerprint does not match the pinned signing key" >&2
    echo "       expected $EXPECTED_FINGERPRINT" >&2
    rm -rf "$workdir"
    return 1
  fi

  mkdir -p "$(dirname "$dest")"
  if ! gpg --homedir "$gnupghome" --batch --quiet --export \
        --export-options export-minimal "$EXPECTED_FINGERPRINT" \
        > "$dest"; then
    echo "error: failed to export verified key to $dest" >&2
    rm -rf "$workdir"
    return 1
  fi
  chmod 644 "$dest"
  rm -rf "$workdir"
  return 0
}

write_signed_sources_list() {
  local list="${1:-$LIST}"
  local keyring="${2:-$KEYRING}"
  cat > "$list" <<EOF
# GTDataworks Portlock — https://gtdataworks.com/portlock
deb [arch=all signed-by=${keyring}] ${REPO_URL} ${CODENAME} main
EOF
  chmod 644 "$list"
}

if [[ "${PORTLOCK_APT_LIB_ONLY:-0}" == 1 ]]; then
  return 0 2>/dev/null || exit 0
fi

# --- goat mode: never leave people stranded without sudo --------------------
if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "==> Portlock apt setup"
  echo "    not root — re-running with sudo (goat mode 🐐)"
  # Prefer re-exec of this file when invoked as a real path
  if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" && "${BASH_SOURCE[0]}" != "-" \
        && "${BASH_SOURCE[0]}" != "/dev/stdin" && "$(basename -- "${BASH_SOURCE[0]}")" != "bash" ]]; then
    exec sudo -E env \
      PORTLOCK_APT_URL="$REPO_URL" \
      PORTLOCK_INSTALL_URL="$INSTALL_URL" \
      PORTLOCK_APT_FINGERPRINT="$EXPECTED_FINGERPRINT" \
      bash "${BASH_SOURCE[0]}" "$@"
  fi
  # curl | bash  →  re-fetch under sudo
  if command -v curl >/dev/null 2>&1; then
    exec sudo -E env \
      PORTLOCK_APT_URL="$REPO_URL" \
      PORTLOCK_INSTALL_URL="$INSTALL_URL" \
      PORTLOCK_APT_FINGERPRINT="$EXPECTED_FINGERPRINT" \
      bash -c "curl --proto '=https' --tlsv1.2 -fsSL \"$INSTALL_URL\" | bash"
  fi
  echo "error: need root. run:  sudo bash $0" >&2
  echo "       or: curl -fsSL $INSTALL_URL | sudo bash" >&2
  exit 1
fi

echo "==> GTDataworks Portlock apt setup"
echo "    repo: $REPO_URL"

require_pinned_fingerprint
require_gpg
fetch_and_verify_key "$KEYRING"
write_signed_sources_list "$LIST" "$KEYRING"
echo "    mode: signed-by (fingerprint ${EXPECTED_FINGERPRINT})"
echo "    wrote $LIST"

apt-get update -o Dir::Etc::sourcelist="$LIST" -o Dir::Etc::sourceparts="-" -o APT::Get::List-Cleanup="0" 2>/dev/null \
  || apt-get update

echo
echo "Repo ready. Install Portlock with:"
echo "  sudo apt install gtdataworks-portlock"
echo "  portlock"
echo
echo "Product: https://gtdataworks.com/portlock"
echo
