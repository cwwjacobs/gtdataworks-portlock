#!/bin/bash
# Build a simple architecture-independent .deb for gtdataworks-portlock.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(tr -d ' \n' <"$ROOT/VERSION")"
PKG="gtdataworks-portlock"
ARCH="all"
STAGE="$ROOT/packaging/deb-root"
DIST="$ROOT/dist"
DEB="${DIST}/${PKG}_${VERSION}_${ARCH}.deb"

rm -rf "$STAGE"
mkdir -p "$STAGE/DEBIAN"
mkdir -p "$STAGE/usr/local/sbin"
mkdir -p "$STAGE/usr/local/bin"
mkdir -p "$STAGE/usr/local/share/gtdataworks-portlock/icons"
mkdir -p "$STAGE/usr/share/polkit-1/actions"
mkdir -p "$STAGE/etc/udev/rules.d"
mkdir -p "$STAGE/etc/gtdataworks-portlock"
mkdir -p "$STAGE/usr/share/doc/${PKG}"
mkdir -p "$DIST"

install -m 0755 "$ROOT/sbin/portlock-ctl" "$STAGE/usr/local/sbin/"
install -m 0755 "$ROOT/sbin/portlock-ctl-auto" "$STAGE/usr/local/sbin/"
install -m 0755 "$ROOT/sbin/portlock-attempt-logger" "$STAGE/usr/local/sbin/"
install -m 0755 "$ROOT/app/portlock.py" "$STAGE/usr/local/share/gtdataworks-portlock/"
install -m 0644 "$ROOT/VERSION" "$STAGE/usr/local/share/gtdataworks-portlock/"
install -m 0644 "$ROOT/udev/99-portlock-block-ms.rules" \
  "$STAGE/usr/local/share/gtdataworks-portlock/"
install -m 0644 "$ROOT/udev/98-portlock-attempt-log.rules" \
  "$STAGE/etc/udev/rules.d/"
# Ship block rule as .disabled in package; postinst enables if missing
install -m 0644 "$ROOT/udev/99-portlock-block-ms.rules" \
  "$STAGE/etc/udev/rules.d/99-portlock-block-ms.rules.disabled"
install -m 0644 "$ROOT/polkit/"*.policy "$STAGE/usr/share/polkit-1/actions/"
install -m 0644 "$ROOT/icons/"*.png "$STAGE/usr/local/share/gtdataworks-portlock/icons/" 2>/dev/null || true
install -m 0644 "$ROOT/icons/"*.svg "$STAGE/usr/local/share/gtdataworks-portlock/icons/" 2>/dev/null || true
install -m 0644 "$ROOT/README.md" "$STAGE/usr/share/doc/${PKG}/"
install -m 0644 "$ROOT/LICENSE" "$STAGE/usr/share/doc/${PKG}/copyright"
install -m 0644 "$ROOT/CHANGELOG.md" "$STAGE/usr/share/doc/${PKG}/changelog"
gzip -9n -f "$STAGE/usr/share/doc/${PKG}/changelog"

cat > "$STAGE/usr/local/bin/gtdataworks-portlock" <<'EOF'
#!/bin/bash
exec /usr/bin/python3 /usr/local/share/gtdataworks-portlock/portlock.py "$@"
EOF
chmod 0755 "$STAGE/usr/local/bin/gtdataworks-portlock"
ln -sfn gtdataworks-portlock "$STAGE/usr/local/bin/portlock"

cat > "$STAGE/DEBIAN/control" <<EOF
Package: ${PKG}
Version: ${VERSION}
Section: utils
Priority: optional
Architecture: ${ARCH}
Depends: python3, python3-gi, gir1.2-gtk-3.0, gir1.2-ayatanaappindicator3-0.1, policykit-1, libnotify-bin
Maintainer: GTDataworks <security@gtdataworks.local>
Description: Tray USB mass-storage lock with auto soft-lock and attempt logging
 GTDataworks Portlock soft-locks USB mass storage on screen lock while
 keeping already-plugged sticks active (write-safe), hard-locks on demand,
 and logs plug-in attempts. Not affiliated with USBGuard.
Homepage: https://github.com/gtdataworks/gtdataworks-portlock
EOF

cat > "$STAGE/DEBIAN/postinst" <<'EOF'
#!/bin/bash
set -e
mkdir -p /var/lib/gtdataworks-portlock /var/log
touch /var/log/portlock-attempts.log
chmod 644 /var/log/portlock-attempts.log
if [[ ! -f /etc/udev/rules.d/99-portlock-block-ms.rules \
   && ! -f /etc/udev/rules.d/99-portlock-block-ms.rules.disabled ]]; then
  cp /usr/local/share/gtdataworks-portlock/99-portlock-block-ms.rules \
     /etc/udev/rules.d/99-portlock-block-ms.rules
  echo hard-locked > /var/lib/gtdataworks-portlock/state
  echo install > /var/lib/gtdataworks-portlock/reason
elif [[ -f /etc/udev/rules.d/99-portlock-block-ms.rules ]]; then
  echo hard-locked > /var/lib/gtdataworks-portlock/state 2>/dev/null || true
else
  echo unlocked > /var/lib/gtdataworks-portlock/state 2>/dev/null || true
fi
# Prefer enabled logger rule from package
udevadm control --reload-rules 2>/dev/null || true
echo "Portlock installed. Run: portlock   (or enable autostart from the app menu)"
echo "Tip: copy desktop file to ~/.config/autostart after first run."
EOF
chmod 0755 "$STAGE/DEBIAN/postinst"

cat > "$STAGE/DEBIAN/prerm" <<'EOF'
#!/bin/bash
set -e
# nothing critical
EOF
chmod 0755 "$STAGE/DEBIAN/prerm"

cat > "$STAGE/DEBIAN/postrm" <<'EOF'
#!/bin/bash
set -e
if [[ "${1:-}" == "purge" ]]; then
  rm -f /etc/udev/rules.d/98-portlock-attempt-log.rules
  rm -f /etc/udev/rules.d/99-portlock-block-ms.rules
  rm -f /etc/udev/rules.d/99-portlock-block-ms.rules.disabled
  rm -rf /var/lib/gtdataworks-portlock /etc/gtdataworks-portlock
  udevadm control --reload-rules 2>/dev/null || true
fi
EOF
chmod 0755 "$STAGE/DEBIAN/postrm"

# Installed-size
SIZE=$(du -sk "$STAGE" | awk '{print $1}')
echo "Installed-Size: $SIZE" >> "$STAGE/DEBIAN/control"

dpkg-deb --build --root-owner-group "$STAGE" "$DEB"
echo "Built $DEB"
ls -lh "$DEB"
