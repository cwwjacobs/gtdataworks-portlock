#!/bin/bash
# Add the GTDataworks Portlock apt repository (run as root).
# Usage: curl -fsSL https://cwwjacobs.github.io/gtdataworks-portlock/install-apt.sh | sudo bash
set -euo pipefail

REPO_URL="${PORTLOCK_APT_URL:-https://cwwjacobs.github.io/gtdataworks-portlock}"
LIST="/etc/apt/sources.list.d/gtdataworks-portlock.list"
KEYRING="/usr/share/keyrings/gtdataworks-portlock.gpg"
CODENAME="stable"

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "error: run as root (sudo)" >&2
  exit 1
fi

echo "==> GTDataworks Portlock apt setup"
echo "    repo: $REPO_URL"

# Prefer signed keyring if KEY.gpg is published
if curl -fsSL "$REPO_URL/KEY.gpg" -o /tmp/portlock-KEY.gpg 2>/dev/null; then
  if command -v gpg >/dev/null 2>&1; then
    install -d -m 0755 /usr/share/keyrings
    gpg --dearmor < /tmp/portlock-KEY.gpg > "$KEYRING"
    chmod 644 "$KEYRING"
    cat > "$LIST" <<EOF
# GTDataworks Portlock — https://github.com/cwwjacobs/gtdataworks-portlock
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
# GTDataworks Portlock — https://github.com/cwwjacobs/gtdataworks-portlock
# Unsigned/static GitHub Pages repo; trusted=yes for bootstrap.
deb [arch=all trusted=yes] ${REPO_URL} ${CODENAME} main
EOF
  echo "    mode: trusted=yes (no KEY.gpg yet)"
fi

chmod 644 "$LIST"
echo "    wrote $LIST"

apt-get update -o Dir::Etc::sourcelist="$LIST" -o Dir::Etc::sourceparts="-" -o APT::Get::List-Cleanup="0" 2>/dev/null \
  || apt-get update

echo
echo "Repo added. Install with:"
echo "  sudo apt install gtdataworks-portlock"
echo "  portlock"
echo
