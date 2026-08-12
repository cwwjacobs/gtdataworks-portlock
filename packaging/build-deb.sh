#!/bin/bash
# Build architecture-independent .deb for GTDataworks Portlock (foundational release).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && cd .. && pwd)"
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
mkdir -p "$STAGE/usr/share/applications"
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
# Ship block rule disabled; postinst hard-locks on fresh install only
install -m 0644 "$ROOT/udev/99-portlock-block-ms.rules" \
  "$STAGE/etc/udev/rules.d/99-portlock-block-ms.rules.disabled"
install -m 0644 "$ROOT/polkit/"*.policy "$STAGE/usr/share/polkit-1/actions/"

# Icons: PNGs only (matrix padlock app art) — skip large source JPEGs
install -m 0644 "$ROOT/icons/"*.png "$STAGE/usr/local/share/gtdataworks-portlock/icons/" 2>/dev/null || true
if [[ -d "$ROOT/icons/hicolor" ]]; then
  mkdir -p "$STAGE/usr/share/icons/hicolor"
  cp -a "$ROOT/icons/hicolor/." "$STAGE/usr/share/icons/hicolor/"
fi

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

# System desktop entry (matrix lock icon via hicolor theme name)
cat > "$STAGE/usr/share/applications/gtdataworks-portlock.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=GTDataworks Portlock
GenericName=USB Port Lock
Comment=Lock USB mass storage, auto soft-lock on lock screen, log plug-in attempts
Exec=gtdataworks-portlock
Icon=gtdataworks-portlock
Terminal=false
Categories=System;Security;
StartupNotify=false
Keywords=USB;security;thumb;drive;portlock;mass-storage;
EOF

cat > "$STAGE/DEBIAN/control" <<EOF
Package: ${PKG}
Version: ${VERSION}
Section: utils
Priority: optional
Architecture: ${ARCH}
Depends: python3, python3-gi, gir1.2-gtk-3.0, gir1.2-ayatanaappindicator3-0.1, policykit-1, libnotify-bin
Maintainer: GTDataworks <cwwjacobs@users.noreply.github.com>
Description: Tray USB mass-storage lock with auto soft-lock and attempt logging
 GTDataworks Portlock is a workstation tray tool that soft-locks USB mass
 storage on screen lock while keeping already-plugged sticks active
 (write-safe), hard-locks on demand, and logs plug-in attempts.
 .
 Foundational v1 release with official matrix padlock icon.
 Not affiliated with the USBGuard project.
Homepage: https://github.com/cwwjacobs/gtdataworks-portlock
EOF

cat > "$STAGE/DEBIAN/postinst" <<'EOF'
#!/bin/bash
set -e
mkdir -p /var/lib/gtdataworks-portlock /var/log
touch /var/log/portlock-attempts.log
chmod 644 /var/log/portlock-attempts.log

# Fresh install: enable hard-lock. Upgrades: never clobber existing policy.
if [[ ! -f /etc/udev/rules.d/99-portlock-block-ms.rules \
   && -f /etc/udev/rules.d/99-portlock-block-ms.rules.disabled ]]; then
  if [[ ! -f /var/lib/gtdataworks-portlock/state ]]; then
    mv /etc/udev/rules.d/99-portlock-block-ms.rules.disabled \
       /etc/udev/rules.d/99-portlock-block-ms.rules
    echo hard-locked > /var/lib/gtdataworks-portlock/state
    echo install > /var/lib/gtdataworks-portlock/reason
  fi
fi

if [[ ! -f /var/lib/gtdataworks-portlock/state ]]; then
  if [[ -f /etc/udev/rules.d/99-portlock-block-ms.rules ]]; then
    echo hard-locked > /var/lib/gtdataworks-portlock/state
  else
    echo unlocked > /var/lib/gtdataworks-portlock/state
  fi
  echo none > /var/lib/gtdataworks-portlock/reason
fi
chmod 644 /var/lib/gtdataworks-portlock/state \
          /var/lib/gtdataworks-portlock/reason 2>/dev/null || true

if command -v udevadm >/dev/null 2>&1; then
  udevadm control --reload-rules 2>/dev/null || true
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache -f /usr/share/icons/hicolor 2>/dev/null || true
fi

echo ""
echo "GTDataworks Portlock installed."
echo "  Start:   portlock   (or Applications → GTDataworks Portlock)"
echo "  Status:  portlock-ctl status   (after install path is on PATH)"
echo "  Docs:    /usr/share/doc/gtdataworks-portlock/"
echo ""
EOF
chmod 0755 "$STAGE/DEBIAN/postinst"

cat > "$STAGE/DEBIAN/prerm" <<'EOF'
#!/bin/bash
set -e
exit 0
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
  if command -v udevadm >/dev/null 2>&1; then
    udevadm control --reload-rules 2>/dev/null || true
  fi
  if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -f /usr/share/icons/hicolor 2>/dev/null || true
  fi
fi
EOF
chmod 0755 "$STAGE/DEBIAN/postrm"

SIZE=$(du -sk "$STAGE" | awk '{print $1}')
echo "Installed-Size: $SIZE" >> "$STAGE/DEBIAN/control"

dpkg-deb --build --root-owner-group "$STAGE" "$DEB"
echo "Built $DEB"
ls -lh "$DEB"
# Quick contents sanity
dpkg-deb -c "$DEB" | grep -E 'portlock-(app|locked|tray)|gtdataworks-portlock.png|applications' | head -30
echo "---"
dpkg-deb -I "$DEB"
