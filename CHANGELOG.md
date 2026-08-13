# Changelog

## 1.0.1 — 2026-08-12

### Hardening release

Security and trust-root fixes on the foundational product cut:

- **Root-to-user symlink boundary removal** — install no longer creates or chowns paths under `$HOME` as root; remaining user artifacts run as the installing user (`runuser`/`sudo -u`)
- **Sticky hard-lock auto-unlock semantics** — session unlock may reverse only `soft-locked` + `reason=auto`; every hard-lock (manual, install, migrated) stays until authenticated unlock
- **Per-session logind scoping/reconciliation** — tray watches this login session’s logind `Lock`/`Unlock` only, with periodic `LockedHint` reconciliation
- **Mandatory signed APT trust** — install and repo build require a pinned 40-hex fingerprint and signed `InRelease`; `signed-by` only, no `trusted=yes`
- **apt autostart** — system `/etc/xdg/autostart` desktop entry so apt installs start the tray
- **Truthful install hard-lock deauthorization** — fresh install/postinst calls `portlock-ctl hard-lock` so attached class-08 interfaces are actually deauthorized
- **sysfs snapshot fix** — mass-storage interface listing resolves real device paths; snapshot is informational only, never an unlock allowlist

## 1.0.0 — 2026-08-12

### Foundational release — first real product cut

Stable public **GTDataworks Portlock**.

- Soft lock / hard lock / unlock state machine
- Auto-lock on session/screen lock (write-safe soft-lock)
- Auto-unlock on session unlock (manual hard-lock preserved)
- Plug-in attempt logging + desktop notifications
- Official neon matrix padlock icon (locked + unlocked + hicolor)
- Tray widget (Ayatana AppIndicator) + CLI helpers
- Shippable **`.deb`** + **public apt repository** (GitHub Pages)
- One-liner: `install-apt.sh` → `apt install gtdataworks-portlock`
- Polkit: passwordless auto path, authenticated manual path

Not affiliated with USBGuard.

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
