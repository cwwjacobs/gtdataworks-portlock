#!/bin/bash
# Remove GTDataworks Portlock system bits. Leaves attempt logs + config.
set -euo pipefail

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  exec sudo "$0" "$@"
fi

USER_NAME="${SUDO_USER:-$USER}"
USER_HOME=$(getent passwd "$USER_NAME" | cut -d: -f6)

as_uninstall_user() {
  local user="$1"
  shift
  if command -v runuser >/dev/null 2>&1; then
    runuser -u "$user" -- "$@"
  else
    sudo -u "$user" -- "$@"
  fi
}

echo "==> Uninstalling GTDataworks Portlock"

# Leave block-rule state as-is (security choice stays with you) unless --open
OPEN=0
if [[ "${1:-}" == "--open" ]]; then
  OPEN=1
fi

rm -f /etc/udev/rules.d/98-portlock-attempt-log.rules
rm -f /usr/local/sbin/portlock-ctl \
      /usr/local/sbin/portlock-ctl-auto \
      /usr/local/sbin/portlock-attempt-logger
rm -f /usr/local/bin/gtdataworks-portlock /usr/local/bin/portlock
rm -f /usr/local/bin/portlock-status \
      /usr/local/bin/portlock-lock \
      /usr/local/bin/portlock-soft \
      /usr/local/bin/portlock-unlock
rm -f /usr/share/polkit-1/actions/com.gtdataworks.portlock.policy \
      /usr/share/polkit-1/actions/com.gtdataworks.portlock.auto.policy
rm -f /usr/share/applications/gtdataworks-portlock.desktop
rm -f /etc/xdg/autostart/gtdataworks-portlock.desktop
rm -rf /usr/local/share/gtdataworks-portlock
rm -rf /etc/gtdataworks-portlock

# User-owned leftovers: unlink as that user, not as root through $HOME.
if [[ -n "$USER_NAME" ]] && id -u "$USER_NAME" >/dev/null 2>&1; then
  as_uninstall_user "$USER_NAME" rm -f \
    "${USER_HOME}/.config/autostart/gtdataworks-portlock.desktop" \
    "${USER_HOME}/.local/share/applications/gtdataworks-portlock.desktop" \
    "${USER_HOME}/.local/bin/portlock-status" \
    "${USER_HOME}/.local/bin/portlock-lock" \
    "${USER_HOME}/.local/bin/portlock-soft" \
    "${USER_HOME}/.local/bin/portlock-unlock" \
    2>/dev/null || true
fi

if [[ "$OPEN" -eq 1 ]]; then
  if [[ -f /etc/udev/rules.d/99-portlock-block-ms.rules ]]; then
    mv /etc/udev/rules.d/99-portlock-block-ms.rules \
       /etc/udev/rules.d/99-portlock-block-ms.rules.disabled
  fi
  echo "    (--open: block rule disabled, ports open for new sticks)"
else
  echo "    Block rule left in place under /etc/udev/rules.d/ (use --open to disable)"
fi

udevadm control --reload-rules || true

echo "Done."
echo "Logs kept: ${USER_HOME}/.local/share/gtdataworks-portlock/"
echo "           /var/log/portlock-attempts.log"
