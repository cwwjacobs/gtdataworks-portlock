#!/bin/bash
# Build a static apt repository from dist/*.deb
# Output: packaging/apt-repo/  (dists/ + pool/)
#
# Signing is mandatory: set GPG_PRIVATE_KEY (armored) or GPG_KEY_ID.
# InRelease must be produced. Unsigned output is not shipped.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DEB="$ROOT/dist"
OUT="${APT_REPO_OUT:-$ROOT/packaging/apt-repo}"
CODENAME="stable"
COMPONENT="main"
ARCH="all"
ORIGIN="GTDataworks"
LABEL="Portlock"
VERSION="$(tr -d ' \n' <"$ROOT/VERSION")"
SIGNING_CONF="$ROOT/packaging/apt-signing.conf"
PLACEHOLDER_FPR="REPLACE_WITH_REPO_SIGNING_FINGERPRINT"

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

read_pinned_fingerprint() {
  local line raw val
  if [[ -n "${PORTLOCK_APT_FINGERPRINT:-}" ]]; then
    printf '%s' "$(normalize_fpr "$PORTLOCK_APT_FINGERPRINT")"
    return 0
  fi
  if [[ -f "$SIGNING_CONF" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
      line="${line%$'\r'}"
      [[ "$line" =~ ^[[:space:]]*# ]] && continue
      [[ "$line" =~ ^[[:space:]]*PORTLOCK_APT_FINGERPRINT= ]] || continue
      raw="${line#*=}"
      val="${raw%%#*}"
      val="${val//[[:space:]]/}"
      val="${val//\"/}"
      val="${val//\'/}"
      printf '%s' "$(normalize_fpr "$val")"
      return 0
    done < "$SIGNING_CONF"
  fi
  printf '%s' "$PLACEHOLDER_FPR"
}

EXPECTED_FINGERPRINT="$(read_pinned_fingerprint)"

if ! is_pinned_fingerprint "$EXPECTED_FINGERPRINT"; then
  echo "error: no authoritative apt signing fingerprint is pinned." >&2
  echo "       Release cannot proceed until the operator sets" >&2
  echo "       PORTLOCK_APT_FINGERPRINT (or packaging/apt-signing.conf)" >&2
  echo "       to the real 40-hex-digit fingerprint of the repo signing key." >&2
  echo "       Do not invent a fingerprint." >&2
  exit 1
fi

if ! command -v gpg >/dev/null 2>&1; then
  echo "error: gpg is required to sign the apt repository" >&2
  exit 1
fi

if [[ -z "${GPG_PRIVATE_KEY:-}" && -z "${GPG_KEY_ID:-}" ]]; then
  echo "error: GPG_PRIVATE_KEY or GPG_KEY_ID is required; unsigned repos are not allowed" >&2
  exit 1
fi

if ! ls "$DIST_DEB"/gtdataworks-portlock_*.deb >/dev/null 2>&1; then
  echo "error: no debs in $DIST_DEB — run make deb first" >&2
  exit 1
fi

rm -rf "$OUT"
mkdir -p "$OUT/pool/${COMPONENT}/g/gtdataworks-portlock"
mkdir -p "$OUT/dists/${CODENAME}/${COMPONENT}/binary-${ARCH}"

cp -a "$DIST_DEB"/gtdataworks-portlock_*.deb \
  "$OUT/pool/${COMPONENT}/g/gtdataworks-portlock/"

# Prefer newest 1.x package only in pool for cleanliness? Keep all versions for upgrade path.
cd "$OUT"
apt-ftparchive packages "pool/${COMPONENT}" > "dists/${CODENAME}/${COMPONENT}/binary-${ARCH}/Packages"
gzip -9n -c "dists/${CODENAME}/${COMPONENT}/binary-${ARCH}/Packages" \
  > "dists/${CODENAME}/${COMPONENT}/binary-${ARCH}/Packages.gz"
# xz optional
if command -v xz >/dev/null 2>&1; then
  xz -9 -c "dists/${CODENAME}/${COMPONENT}/binary-${ARCH}/Packages" \
    > "dists/${CODENAME}/${COMPONENT}/binary-${ARCH}/Packages.xz" || true
fi

cat > "dists/${CODENAME}/${COMPONENT}/binary-${ARCH}/Release" <<EOF
Archive: ${CODENAME}
Component: ${COMPONENT}
Origin: ${ORIGIN}
Label: ${LABEL}
Architecture: ${ARCH}
EOF

# Top-level Release
apt-ftparchive \
  -o "APT::FTPArchive::Release::Origin=${ORIGIN}" \
  -o "APT::FTPArchive::Release::Label=${LABEL}" \
  -o "APT::FTPArchive::Release::Suite=${CODENAME}" \
  -o "APT::FTPArchive::Release::Codename=${CODENAME}" \
  -o "APT::FTPArchive::Release::Architectures=${ARCH}" \
  -o "APT::FTPArchive::Release::Components=${COMPONENT}" \
  -o "APT::FTPArchive::Release::Description=GTDataworks Portlock apt repository" \
  release "dists/${CODENAME}" > "dists/${CODENAME}/Release"

sign_release() {
  local keyring_args=()
  local kid
  if [[ -n "${GPG_PRIVATE_KEY:-}" ]]; then
    local gnupghome
    gnupghome="$(mktemp -d)"
    export GNUPGHOME="$gnupghome"
    chmod 700 "$gnupghome"
    echo "$GPG_PRIVATE_KEY" | gpg --batch --import
    kid=$(gpg --list-secret-keys --with-colons | awk -F: '/^fpr:/ {print $10; exit}')
    gpg --batch --yes --pinentry-mode loopback \
      --default-key "$kid" \
      -abs -o "dists/${CODENAME}/Release.gpg" "dists/${CODENAME}/Release"
    gpg --batch --yes --pinentry-mode loopback \
      --default-key "$kid" \
      --clearsign -o "dists/${CODENAME}/InRelease" "dists/${CODENAME}/Release"
    gpg --armor --export "$kid" > "$OUT/KEY.gpg"
    rm -rf "$gnupghome"
    unset GNUPGHOME
  elif [[ -n "${GPG_KEY_ID:-}" ]]; then
    kid="$GPG_KEY_ID"
    gpg --batch --yes -abs -o "dists/${CODENAME}/Release.gpg" "dists/${CODENAME}/Release"
    gpg --batch --yes --clearsign -o "dists/${CODENAME}/InRelease" "dists/${CODENAME}/Release"
    gpg --armor --export "$GPG_KEY_ID" > "$OUT/KEY.gpg"
  fi
}

sign_release

if [[ ! -f "$OUT/dists/${CODENAME}/InRelease" || ! -s "$OUT/dists/${CODENAME}/InRelease" ]]; then
  echo "error: InRelease was not produced; refusing to ship an unsigned repo" >&2
  exit 1
fi
if [[ ! -f "$OUT/KEY.gpg" || ! -s "$OUT/KEY.gpg" ]]; then
  echo "error: KEY.gpg was not produced" >&2
  exit 1
fi

ACTUAL_FPR="$(gpg --batch --with-colons --show-keys "$OUT/KEY.gpg" 2>/dev/null \
  | awk -F: '/^fpr:/ {print $10; exit}')"
ACTUAL_FPR="$(normalize_fpr "$ACTUAL_FPR")"
if [[ "$ACTUAL_FPR" != "$EXPECTED_FINGERPRINT" ]]; then
  echo "error: signing key fingerprint $ACTUAL_FPR does not match pin $EXPECTED_FINGERPRINT" >&2
  echo "       the installer will reject this KEY.gpg; refusing to ship" >&2
  exit 1
fi

# Landing page for GitHub Pages root (when OUT is published at site root under /apt or full root)
cat > "$OUT/index.html" <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>GTDataworks Portlock — apt repo</title>
  <style>
    :root { color-scheme: dark; }
    body { font-family: ui-sans-serif, system-ui, sans-serif; max-width: 42rem;
           margin: 3rem auto; padding: 0 1.25rem; background: #0a0a0a; color: #d4f5d4;
           line-height: 1.55; }
    h1 { color: #39ff14; font-weight: 700; letter-spacing: -0.02em; }
    a { color: #7dff9a; }
    code, pre { background: #141414; border-radius: 8px; }
    code { padding: 0.15em 0.4em; }
    pre { padding: 1rem 1.1rem; overflow-x: auto; border: 1px solid #1f3d1f; }
    .muted { color: #8a9a8a; font-size: 0.95rem; }
    .badge { display: inline-block; border: 1px solid #39ff14; color: #39ff14;
             padding: 0.15rem 0.55rem; border-radius: 999px; font-size: 0.8rem; }
  </style>
</head>
<body>
  <p class="badge">v${VERSION} · signed apt</p>
  <h1>Portlock apt repository</h1>
  <p>Workstation USB mass-storage lock — soft-lock on screen lock, hard-lock when you leave, attempt logging. Official matrix padlock build.</p>
  <h2>Install</h2>
  <pre>curl -fsSL https://cwwjacobs.github.io/gtdataworks-portlock/install-apt.sh | sudo bash
sudo apt update
sudo apt install gtdataworks-portlock
portlock</pre>
  <p class="muted">Or pin a release <code>.deb</code> from
    <a href="https://github.com/cwwjacobs/gtdataworks-portlock/releases">GitHub Releases</a>.</p>
  <p class="muted">Repo layout: <code>dists/</code> + <code>pool/</code> · suite <code>${CODENAME}</code> · signed: required</p>
</body>
</html>
EOF

echo "apt repo built at $OUT (signed=1 fingerprint=${EXPECTED_FINGERPRINT})"
echo "packages:"
grep -E '^Package:|^Version:|^Filename:' "dists/${CODENAME}/${COMPONENT}/binary-${ARCH}/Packages" || true
