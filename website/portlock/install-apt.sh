#!/bin/bash
# GTDataworks Portlock — add the public apt repository.
#
#   curl -fsSL https://gtdataworks.com/portlock/install-apt.sh | bash
#   # forgot sudo? goat mode re-runs elevated for you.
#
# Or:  sudo bash install-apt.sh
set -euo pipefail

REPO_URL="${PORTLOCK_APT_URL:-https://cwwjacobs.github.io/gtdataworks-portlock}"
# Script location for re-fetch under sudo (curl | bash)
INSTALL_URL="${PORTLOCK_INSTALL_URL:-https://gtdataworks.com/portlock/install-apt.sh}"
LIST="/etc/apt/sources.list.d/gtdataworks-portlock.list"
KEYRING="/usr/share/keyrings/gtdataworks-portlock.gpg"
CODENAME="stable"

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
      bash "${BASH_SOURCE[0]}" "$@"
  fi
  # curl | bash  →  re-fetch under sudo
  if command -v curl >/dev/null 2>&1; then
    exec sudo -E env \
      PORTLOCK_APT_URL="$REPO_URL" \
      PORTLOCK_INSTALL_URL="$INSTALL_URL" \
      bash -c "curl -fsSL \"$INSTALL_URL\" | bash"
  fi
  echo "error: need root. run:  sudo bash $0" >&2
  echo "       or: curl -fsSL $INSTALL_URL | sudo bash" >&2
  exit 1
fi

echo "==> GTDataworks Portlock apt setup"
echo "    repo: $REPO_URL"

if curl -fsSL "$REPO_URL/KEY.gpg" -o /tmp/portlock-KEY.gpg 2>/dev/null; then
  if command -v gpg >/dev/null 2>&1; then
    install -d -m 0755 /usr/share/keyrings
    gpg --dearmor < /tmp/portlock-KEY.gpg > "$KEYRING"
    chmod 644 "$KEYRING"
    cat > "$LIST" <<EOF
# GTDataworks Portlock — https://gtdataworks.com/portlock
deb [arch=all signed-by=${KEYRING}] ${REPO_URL} ${CODENAME} main
EOF
    echo "    mode: signed (signed-by keyring)"
  else
    cat > "$LIST" <<EOF
deb [arch=all trusted=yes] ${REPO_URL} ${CODENAME} main
EOF
    echo "    mode: trusted=yes (gpg not installed)"
  fi
  rm -f /tmp/portlock-KEY.gpg
else
  cat > "$LIST" <<EOF
# GTDataworks Portlock — https://gtdataworks.com/portlock
# Public apt repo (GitHub Pages). trusted=yes until KEY.gpg is published.
deb [arch=all trusted=yes] ${REPO_URL} ${CODENAME} main
EOF
  echo "    mode: trusted=yes (no KEY.gpg yet)"
fi

chmod 644 "$LIST"
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
