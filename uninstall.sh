#!/bin/bash
# Remove GTDataworks Portlock system bits. Leaves attempt logs + config.
set -euo pipefail

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  exec sudo "$0" "$@"
fi

USER_NAME="${SUDO_USER:-$USER}"
USER_HOME=$(getent passwd "$USER_NAME" | cut -d: -f6)

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
rm -f /usr/share/polkit-1/actions/com.gtdataworks.portlock.policy \
      /usr/share/polkit-1/actions/com.gtdataworks.portlock.auto.policy
rm -rf /usr/local/share/gtdataworks-portlock
rm -rf /etc/gtdataworks-portlock
rm -f "$USER_HOME/.config/autostart/gtdataworks-portlock.desktop"
rm -f "$USER_HOME/.local/share/applications/gtdataworks-portlock.desktop"
rm -f "$USER_HOME/.local/bin/portlock-status" \
      "$USER_HOME/.local/bin/portlock-lock" \
      "$USER_HOME/.local/bin/portlock-soft" \
      "$USER_HOME/.local/bin/portlock-unlock"

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
echo "Logs kept: $USER_HOME/.local/share/gtdataworks-portlock/"
echo "           /var/log/portlock-attempts.log"
