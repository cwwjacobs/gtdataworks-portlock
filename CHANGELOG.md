# Changelog

## 0.2.1 — 2026-08-12

- Official matrix padlock app icon (locked + unlocked tray states)
- Freedesktop hicolor icon theme install for menu/launcher

## 0.2.0 — 2026-08-12

- Rebranded to **GTDataworks Portlock** (`gtdataworks-portlock`)
- **Auto-lock mode**: soft-lock on session/screen lock
  - Already-plugged mass storage stays authorized (write-safe)
  - New sticks blocked + logged while locked
  - Unplug while locked → cannot re-insert until ports open
- **Hard lock** vs **soft lock** state machine
- Passwordless polkit path for auto soft-lock / auto-unlock
- Manual hard-lock survives session unlock until you unlock ports
- Attempt log + tray notifications
- Migrates legacy `usb-storage-guard` rules/logs on install

## 0.1.0 — 2026-08-12

- Initial tray widget (usb-storage-guard): lock/unlock + attempt tracking
