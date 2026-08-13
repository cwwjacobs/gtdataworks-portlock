#!/bin/bash
# Install GTDataworks Portlock (system + user tray autostart).
set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)"
VERSION="$(tr -d ' \n' <"$SRC/VERSION" 2>/dev/null || echo 0.2.0)"
USER_NAME="${SUDO_USER:-$USER}"
USER_HOME=$(getent passwd "$USER_NAME" | cut -d: -f6)
if [[ -z "$USER_HOME" ]]; then
  USER_HOME="$HOME"
fi

as_install_user() {
  # Run as the installing user so root never follows user-controlled path
  # components (symlinks under $HOME).
  local user="$1"
  shift
  if command -v runuser >/dev/null 2>&1; then
    runuser -u "$user" -- "$@"
  else
    sudo -u "$user" -- "$@"
  fi
}

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "Re-running installer with sudo..."
  exec sudo -E "$0" "$@"
fi

echo "==> Installing GTDataworks Portlock v${VERSION}"

# --- remove legacy usb-storage-guard bits (keep logs) -----------------------
if [[ -f /etc/udev/rules.d/98-usb-ms-attempt-log.rules ]]; then
  rm -f /etc/udev/rules.d/98-usb-ms-attempt-log.rules
  echo "    (removed legacy attempt-log udev rule)"
fi
rm -f /usr/local/sbin/usb-storage-guard-ctl \
      /usr/local/sbin/usb-ms-attempt-logger \
      /usr/local/bin/usb-storage-guard \
      /usr/share/polkit-1/actions/com.local.usb-storage-guard.policy 2>/dev/null || true
rm -rf /usr/local/share/usb-storage-guard 2>/dev/null || true
# User-owned leftover desktop files: unlink as that user, not as root.
if [[ -n "$USER_NAME" ]] && id -u "$USER_NAME" >/dev/null 2>&1; then
  as_install_user "$USER_NAME" rm -f \
    "${USER_HOME}/.config/autostart/usb-storage-guard.desktop" \
    "${USER_HOME}/.local/share/applications/usb-storage-guard.desktop" \
    2>/dev/null || true
fi

# Migrate old block rule path if present
if [[ -f /etc/udev/rules.d/99-block-usb-mass-storage.rules \
   && ! -f /etc/udev/rules.d/99-portlock-block-ms.rules \
   && ! -f /etc/udev/rules.d/99-portlock-block-ms.rules.disabled ]]; then
  mv /etc/udev/rules.d/99-block-usb-mass-storage.rules \
     /etc/udev/rules.d/99-portlock-block-ms.rules
  echo "    (migrated legacy block rule → portlock)"
fi
if [[ -f /etc/udev/rules.d/99-block-usb-mass-storage.rules.disabled \
   && ! -f /etc/udev/rules.d/99-portlock-block-ms.rules \
   && ! -f /etc/udev/rules.d/99-portlock-block-ms.rules.disabled ]]; then
  mv /etc/udev/rules.d/99-block-usb-mass-storage.rules.disabled \
     /etc/udev/rules.d/99-portlock-block-ms.rules.disabled
fi
rm -f /etc/udev/rules.d/99-block-usb-mass-storage.rules \
      /etc/udev/rules.d/99-block-usb-mass-storage.rules.disabled 2>/dev/null || true

# --- directories (root-controlled only) -------------------------------------
install -d /usr/local/sbin
install -d /usr/local/bin
install -d /usr/local/share/gtdataworks-portlock/icons
install -d /var/lib/gtdataworks-portlock
install -d /etc/gtdataworks-portlock
install -d /var/log
install -d /usr/share/applications
install -d /etc/xdg/autostart

# --- binaries ---------------------------------------------------------------
install -m 0755 "$SRC/sbin/portlock-ctl" /usr/local/sbin/portlock-ctl
install -m 0755 "$SRC/sbin/portlock-ctl-auto" /usr/local/sbin/portlock-ctl-auto
install -m 0755 "$SRC/sbin/portlock-attempt-logger" /usr/local/sbin/portlock-attempt-logger
install -m 0755 "$SRC/app/portlock.py" /usr/local/share/gtdataworks-portlock/portlock.py
install -m 0644 "$SRC/VERSION" /usr/local/share/gtdataworks-portlock/VERSION
install -m 0644 "$SRC/udev/99-portlock-block-ms.rules" \
  /usr/local/share/gtdataworks-portlock/99-portlock-block-ms.rules
install -m 0644 "$SRC/icons/"*.png /usr/local/share/gtdataworks-portlock/icons/ 2>/dev/null || true
install -m 0644 "$SRC/icons/"*.jpg /usr/local/share/gtdataworks-portlock/icons/ 2>/dev/null || true
# Freedesktop theme icons (menu / launcher)
if [[ -d "$SRC/icons/hicolor" ]]; then
  for dir in "$SRC/icons/hicolor"/*/apps; do
    [[ -d "$dir" ]] || continue
    size=$(basename "$(dirname "$dir")")
    install -d "/usr/share/icons/hicolor/${size}/apps"
    install -m 0644 "$dir/"*.png "/usr/share/icons/hicolor/${size}/apps/" 2>/dev/null || true
  done
  if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -f /usr/share/icons/hicolor 2>/dev/null || true
  fi
fi

install -m 0644 "$SRC/udev/98-portlock-attempt-log.rules" \
  /etc/udev/rules.d/98-portlock-attempt-log.rules

# Block rule: keep existing state; default LOCKED (hard) on fresh install.
# Declaring hard-locked must actually deauthorize attached class-08 interfaces.
if [[ ! -f /etc/udev/rules.d/99-portlock-block-ms.rules \
   && ! -f /etc/udev/rules.d/99-portlock-block-ms.rules.disabled ]]; then
  /usr/local/sbin/portlock-ctl hard-lock install
  echo "    (fresh install — ports HARD-LOCKED by default)"
else
  if [[ -f /etc/udev/rules.d/99-portlock-block-ms.rules ]]; then
    if [[ ! -f /var/lib/gtdataworks-portlock/state ]]; then
      /usr/local/sbin/portlock-ctl hard-lock migrated
    fi
  else
    if [[ ! -f /var/lib/gtdataworks-portlock/state ]]; then
      echo "unlocked" > /var/lib/gtdataworks-portlock/state
      echo "none" > /var/lib/gtdataworks-portlock/reason
    fi
  fi
  echo "    (kept existing lock state)"
fi

install -m 0644 "$SRC/polkit/com.gtdataworks.portlock.policy" \
  /usr/share/polkit-1/actions/com.gtdataworks.portlock.policy
install -m 0644 "$SRC/polkit/com.gtdataworks.portlock.auto.policy" \
  /usr/share/polkit-1/actions/com.gtdataworks.portlock.auto.policy

# Who gets desktop notifications from udev logger (parsed, never sourced)
if [[ "$USER_NAME" =~ ^[A-Za-z_][A-Za-z0-9_-]*$ ]]; then
  printf '# Written by install.sh — user for attempt notifications\nNOTIFY_USER=%s\n' \
    "$USER_NAME" > /etc/gtdataworks-portlock/notify-user.conf
else
  printf '# Written by install.sh — no safe NOTIFY_USER\n' \
    > /etc/gtdataworks-portlock/notify-user.conf
fi
chmod 644 /etc/gtdataworks-portlock/notify-user.conf

# Launcher
cat > /usr/local/bin/gtdataworks-portlock <<'EOF'
#!/bin/bash
exec /usr/bin/python3 /usr/local/share/gtdataworks-portlock/portlock.py "$@"
EOF
chmod 0755 /usr/local/bin/gtdataworks-portlock
ln -sfn gtdataworks-portlock /usr/local/bin/portlock

# CLI helpers (root-controlled; do not write under $HOME)
cat > /usr/local/bin/portlock-status <<'EOF'
#!/bin/bash
/usr/local/sbin/portlock-ctl json-status
EOF
cat > /usr/local/bin/portlock-lock <<'EOF'
#!/bin/bash
pkexec /usr/local/sbin/portlock-ctl hard-lock manual
EOF
cat > /usr/local/bin/portlock-soft <<'EOF'
#!/bin/bash
pkexec /usr/local/sbin/portlock-ctl soft-lock manual
EOF
cat > /usr/local/bin/portlock-unlock <<'EOF'
#!/bin/bash
pkexec /usr/local/sbin/portlock-ctl unlock
EOF
chmod 0755 /usr/local/bin/portlock-status \
           /usr/local/bin/portlock-lock \
           /usr/local/bin/portlock-soft \
           /usr/local/bin/portlock-unlock

# Desktop launcher + system XDG autostart (not under $HOME)
DESKTOP_BODY='[Desktop Entry]
Type=Application
Name=GTDataworks Portlock
GenericName=USB Port Lock
Comment=Lock USB mass storage, auto soft-lock on lock screen, log plug-in attempts
Exec=/usr/local/bin/gtdataworks-portlock
Icon=gtdataworks-portlock
Terminal=false
Categories=System;Security;
StartupNotify=false
Keywords=USB;security;thumb;drive;portlock;
X-GNOME-Autostart-enabled=true
'
printf '%s' "$DESKTOP_BODY" > /usr/share/applications/gtdataworks-portlock.desktop
printf '%s' "$DESKTOP_BODY" > /etc/xdg/autostart/gtdataworks-portlock.desktop
chmod 644 /usr/share/applications/gtdataworks-portlock.desktop \
          /etc/xdg/autostart/gtdataworks-portlock.desktop

# User config/log (optional source-install UX) — created as the user only.
if [[ -n "$USER_NAME" ]] && id -u "$USER_NAME" >/dev/null 2>&1; then
  as_install_user "$USER_NAME" mkdir -p \
    "${USER_HOME}/.local/share/gtdataworks-portlock" \
    "${USER_HOME}/.config/gtdataworks-portlock"
  if ! as_install_user "$USER_NAME" test -f \
      "${USER_HOME}/.config/gtdataworks-portlock/config.json"; then
    as_install_user "$USER_NAME" tee \
      "${USER_HOME}/.config/gtdataworks-portlock/config.json" >/dev/null <<'EOF'
{
  "auto_lock": true,
  "auto_unlock_on_session_unlock": true,
  "notify_on_auto": true
}
EOF
  fi
  as_install_user "$USER_NAME" touch \
    "${USER_HOME}/.local/share/gtdataworks-portlock/attempts.log"
  LEGACY_LOG="${USER_HOME}/.local/share/usb-storage-guard/attempts.log"
  if as_install_user "$USER_NAME" test -f "$LEGACY_LOG" \
     && ! as_install_user "$USER_NAME" test -s \
        "${USER_HOME}/.local/share/gtdataworks-portlock/attempts.log"; then
    as_install_user "$USER_NAME" cp "$LEGACY_LOG" \
      "${USER_HOME}/.local/share/gtdataworks-portlock/attempts.log"
    echo "    (migrated legacy attempt log)"
  fi
fi

touch /var/log/portlock-attempts.log
chmod 644 /var/log/portlock-attempts.log
chmod 644 /var/lib/gtdataworks-portlock/state /var/lib/gtdataworks-portlock/reason 2>/dev/null || true

udevadm control --reload-rules
udevadm trigger --subsystem-match=usb || true

echo
echo "Installed GTDataworks Portlock v${VERSION}"
echo "  Tray:     portlock  /  gtdataworks-portlock   (autostart)"
echo "  CLI:      portlock-lock | portlock-soft | portlock-unlock | portlock-status"
echo "  Log:      /var/log/portlock-attempts.log"
echo "  Auto-lock: ON (soft-lock at lock screen; active sticks preserved)"
echo

if [[ -n "${DISPLAY:-}" || -n "${WAYLAND_DISPLAY:-}" ]]; then
  as_install_user "$USER_NAME" env \
    DISPLAY="${DISPLAY:-:0}" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u "$USER_NAME")/bus" \
    XDG_RUNTIME_DIR="/run/user/$(id -u "$USER_NAME")" \
    /usr/local/bin/gtdataworks-portlock >/dev/null 2>&1 &
  echo "  Tray launched."
else
  echo "  Start from menu: GTDataworks Portlock"
fi
