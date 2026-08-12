# GTDataworks Portlock

**Desktop USB mass-storage lock with Auto-lock, write-safe soft-lock, and plug-in attempt logging.**

> Not affiliated with [USBGuard](https://usbguard.github.io/). Portlock is a small workstation tray tool; USBGuard is a full USB authorization framework. They solve related problems at different layers.

![status](https://img.shields.io/badge/version-0.2.0-blue) ![license](https://img.shields.io/badge/license-MIT-green) ![platform](https://img.shields.io/badge/platform-Linux-lightgrey)

---

## What it does

| Feature | Behavior |
|--------|----------|
| **Soft lock** | Blocks *new* USB mass-storage devices. Sticks already plugged in **stay active** so writes are not interrupted. |
| **Hard lock** | Blocks everything now — deauthorizes active sticks too. “I’m leaving the house.” |
| **Auto-lock** | On lock screen / session lock → **soft-lock** (passwordless). |
| **Auto-unlock** | On session unlock → ports open again (optional; default on). Manual hard-lock is kept until you unlock. |
| **Attempt log** | Every mass-storage plug is logged (VID/PID, serial, product) + desktop notification. |
| **Tray widget** | Red / green icon, one-click actions (Cinnamon, MATE, others with AppIndicator). |

Only **USB class 08** (mass storage) is targeted. Keyboards, mice, Bluetooth dongles, etc. keep working.

---

## Auto-lock ruleset (the important bit)

Designed so locking the screen never kills an in-progress copy:

1. **Unlock your session** and **plug the stick before** you lock the screen.
2. When the **lock screen appears**, Portlock **soft-locks**:
   - Already-plugged sticks **stay authorized** (safe for writes).
   - Any **new** stick is **blocked** and **logged**.
3. If you **unplug** while locked, you **cannot re-insert** until ports open again.
4. **Unlock the session** → ports auto-open for new sticks (toggleable).
5. **Hard lock** from the tray = block all mass storage immediately; survives session unlock until you manually unlock ports.

```
         unlock session
               │
               ▼
     ┌───────────────────┐
     │  ports OPEN       │◄──── plug stick here if you need it
     │  (new sticks ok)  │
     └─────────┬─────────┘
               │ lock screen (Auto-lock on)
               ▼
     ┌───────────────────┐
     │  SOFT LOCK        │──── active sticks keep writing
     │  new sticks BLOCK │──── unplug = gone until unlock
     └─────────┬─────────┘
               │ unlock session
               ▼
            ports OPEN
```

---

## Quick install

```bash
git clone https://github.com/YOUR_USER/gtdataworks-portlock.git
cd gtdataworks-portlock
./install.sh
```

Requires: Linux with udev, polkit/`pkexec`, Python 3 + Gtk 3 + Ayatana AppIndicator (Linux Mint / Ubuntu / Cinnamon friendly).

```bash
# Debian/Ubuntu/Mint deps
sudo apt install python3-gi gir1.2-gtk-3.0 gir1.2-ayatanaappindicator3-0.1 policykit-1
```

Fresh install defaults to **hard-locked** until you unlock once from the tray (password prompt). After that, Auto-lock soft-locks without a password.

### CLI

```bash
portlock-status          # JSON state
portlock-soft            # soft lock (keep active sticks)
portlock-lock            # hard lock
portlock-unlock          # open ports
```

### Uninstall

```bash
./uninstall.sh           # keeps block rule as-is
./uninstall.sh --open    # also open ports
```

---

## Configuration

`~/.config/gtdataworks-portlock/config.json`

```json
{
  "auto_lock": true,
  "auto_unlock_on_session_unlock": true,
  "notify_on_auto": true
}
```

Also toggle from the tray menu.

**Logs**

| Path | What |
|------|------|
| `~/.local/share/gtdataworks-portlock/attempts.log` | User-readable attempt log |
| `/var/log/portlock-attempts.log` | System copy |
| `/var/lib/gtdataworks-portlock/state` | `unlocked` / `soft-locked` / `hard-locked` |

---

## How it works (technical)

- **udev** rule on USB interface class `08` sets `authorized=0` when the block rule file is present.
- **Soft lock** installs that rule and **does not** poke currently authorized interfaces.
- **Hard lock** installs the rule **and** writes `0` to every mass-storage interface’s `authorized`.
- **Auto path** uses `portlock-ctl-auto` + polkit action `com.gtdataworks.portlock.auto` with `allow_active=yes` so screen-lock does not prompt for a password.
- Manual lock/unlock uses `portlock-ctl` + polkit `auth_admin_keep`.
- Tray watches Cinnamon/GNOME/MATE screensaver `ActiveChanged` and logind `Lock`/`Unlock`.

---

## Package as `.deb`

```bash
make deb
# → dist/gtdataworks-portlock_0.2.0_all.deb
```

---

## Security notes

- This is **physical-access hygiene**, not a substitute for full-disk encryption, screen lock, or [USBGuard](https://usbguard.github.io/) allowlists.
- Soft-lock trusts sticks that were already authorized when the screen locked.
- Auto soft-lock is passwordless for the **active local seat** by design; hard-lock still requires admin auth.
- Root can always undo everything.

---

## Project layout

```
gtdataworks-portlock/
  app/portlock.py           # tray widget
  sbin/portlock-ctl         # privileged control
  sbin/portlock-ctl-auto    # auto soft-lock / unlock only
  sbin/portlock-attempt-logger
  udev/                     # block + log rules
  polkit/                   # manual + auto policies
  packaging/build-deb.sh
  install.sh  uninstall.sh
```

---

## License

MIT © GTDataworks — see [LICENSE](LICENSE).

---

## Name

**Portlock** — lock the USB ports for removable storage when you’re not looking; keep honest work (and in-flight writes) intact when you are.
