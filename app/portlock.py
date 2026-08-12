#!/usr/bin/env python3
"""
GTDataworks Portlock — tray widget for USB mass-storage lock + attempt log.

Auto-lock mode (default on):
  • Session/screen locks  → soft-lock: NEW sticks blocked; already-plugged stay live
  • Session/screen unlocks → unlock ports (unless you hard-locked manually)
  • Unplug while locked    → cannot re-insert until ports unlock
  • Manual hard-lock       → kills active sticks too (leave-the-house mode)
"""

from __future__ import annotations

import json
import os
import signal
import subprocess
import sys
from datetime import datetime
from pathlib import Path

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("Gio", "2.0")
try:
    gi.require_version("AyatanaAppIndicator3", "0.1")
    from gi.repository import AyatanaAppIndicator3 as AppIndicator3
except ValueError:
    gi.require_version("AppIndicator3", "0.1")
    from gi.repository import AppIndicator3  # type: ignore

from gi.repository import GLib, Gtk, Gio

APP_ID = "gtdataworks-portlock"
APP_NAME = "Portlock"
VERSION = "0.2.0"

HOME = Path.home()
CONFIG_DIR = HOME / ".config" / "gtdataworks-portlock"
CONFIG_PATH = CONFIG_DIR / "config.json"
DATA_DIR = HOME / ".local" / "share" / "gtdataworks-portlock"
USER_LOG = DATA_DIR / "attempts.log"
# legacy log path from usb-storage-guard
LEGACY_LOG = HOME / ".local" / "share" / "usb-storage-guard" / "attempts.log"
SYSTEM_LOG = Path("/var/log/portlock-attempts.log")
NOTIFY_FLAG = DATA_DIR / "notify.flag"
CTL = Path("/usr/local/sbin/portlock-ctl")
CTL_AUTO = Path("/usr/local/sbin/portlock-ctl-auto")
ICON_DIR = Path("/usr/local/share/gtdataworks-portlock/icons")
if not ICON_DIR.is_dir():
    ICON_DIR = Path(__file__).resolve().parent.parent / "icons"

POLL_MS = 2500

DEFAULT_CONFIG = {
    "auto_lock": True,
    "auto_unlock_on_session_unlock": True,
    "notify_on_auto": True,
}


def load_config() -> dict:
    cfg = dict(DEFAULT_CONFIG)
    if CONFIG_PATH.is_file():
        try:
            data = json.loads(CONFIG_PATH.read_text())
            if isinstance(data, dict):
                cfg.update({k: data[k] for k in DEFAULT_CONFIG if k in data})
        except (OSError, json.JSONDecodeError):
            pass
    return cfg


def save_config(cfg: dict) -> None:
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    CONFIG_PATH.write_text(json.dumps(cfg, indent=2) + "\n")


def run_cmd(args: list[str], timeout: float = 30) -> subprocess.CompletedProcess:
    return subprocess.run(
        args, capture_output=True, text=True, timeout=timeout, check=False
    )


def get_state() -> str:
    if CTL.is_file():
        r = run_cmd([str(CTL), "status"], timeout=5)
        out = (r.stdout or "").strip()
        if out in ("unlocked", "soft-locked", "hard-locked"):
            return out
        if out == "locked":
            return "hard-locked"
    if Path("/etc/udev/rules.d/99-portlock-block-ms.rules").is_file():
        return "hard-locked"
    if Path("/etc/udev/rules.d/99-block-usb-mass-storage.rules").is_file():
        return "hard-locked"
    return "unlocked"


def get_reason() -> str:
    if CTL.is_file():
        r = run_cmd([str(CTL), "reason"], timeout=5)
        return (r.stdout or "").strip() or "none"
    return "none"


def privileged(action: str, *extra: str, auto: bool = False) -> tuple[bool, str]:
    """Run portlock-ctl via pkexec. auto=True uses passwordless auto wrapper."""
    if auto:
        if not CTL_AUTO.is_file():
            return False, "portlock-ctl-auto not installed — run install.sh"
        r = run_cmd(["pkexec", str(CTL_AUTO), action, *extra], timeout=60)
    else:
        if not CTL.is_file():
            return False, "portlock-ctl not installed — run install.sh"
        r = run_cmd(["pkexec", str(CTL), action, *extra], timeout=120)
    out = ((r.stdout or "") + (r.stderr or "")).strip()
    if r.returncode != 0:
        return False, out or f"pkexec failed ({r.returncode})"
    return True, out or action


def attempt_log_path() -> Path:
    if USER_LOG.is_file():
        return USER_LOG
    if LEGACY_LOG.is_file():
        return LEGACY_LOG
    if SYSTEM_LOG.is_file():
        return SYSTEM_LOG
    return USER_LOG


def read_attempts(limit: int | None = None) -> list[str]:
    path = attempt_log_path()
    if not path.is_file():
        return []
    try:
        lines = path.read_text(errors="replace").splitlines()
    except OSError:
        return []
    return lines[-limit:] if limit is not None else lines


def count_attempts() -> int:
    return len(read_attempts())


def count_blocked() -> int:
    return sum(
        1
        for line in read_attempts()
        if any(
            s in line
            for s in (
                "state=soft-locked",
                "state=hard-locked",
                "state=locked",
            )
        )
    )


def parse_line(line: str) -> dict:
    data = {
        "raw": line,
        "ts": "",
        "state": "?",
        "product": "",
        "vidpid": "",
        "serial": "",
    }
    parts = line.split(" ", 1)
    data["ts"] = parts[0] if parts else ""
    rest = parts[1] if len(parts) > 1 else line

    def grab(key: str) -> str:
        token = f"{key}="
        if token not in rest:
            return ""
        after = rest.split(token, 1)[1]
        if after.startswith('"'):
            end = after.find('"', 1)
            return after[1:end] if end != -1 else after[1:]
        return after.split(" ", 1)[0]

    data["state"] = grab("state") or "?"
    man = grab("manufacturer")
    prod = grab("product")
    data["product"] = f"{man} {prod}".strip()
    vid, pid = grab("vid"), grab("pid")
    data["vidpid"] = f"{vid}:{pid}" if vid or pid else ""
    data["serial"] = grab("serial")
    return data


def state_label(state: str) -> str:
    return {
        "unlocked": "OPEN — new sticks allowed",
        "soft-locked": "SOFT LOCK — new sticks blocked, active kept",
        "hard-locked": "HARD LOCK — all mass storage blocked",
    }.get(state, state)


class AttemptWindow(Gtk.Window):
    def __init__(self, app: "PortlockApp"):
        super().__init__(title=f"{APP_NAME} — attempt log")
        self.app = app
        self.set_default_size(760, 440)
        self.set_border_width(8)
        self.set_position(Gtk.WindowPosition.CENTER)

        vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        self.add(vbox)

        header = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        self.summary = Gtk.Label(xalign=0)
        header.pack_start(self.summary, True, True, 0)
        btn_refresh = Gtk.Button(label="Refresh")
        btn_refresh.connect("clicked", lambda *_: self.reload())
        header.pack_end(btn_refresh, False, False, 0)
        btn_clear = Gtk.Button(label="Clear user log…")
        btn_clear.connect("clicked", self.on_clear)
        header.pack_end(btn_clear, False, False, 0)
        vbox.pack_start(header, False, False, 0)

        scroll = Gtk.ScrolledWindow()
        scroll.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC)
        vbox.pack_start(scroll, True, True, 0)

        self.store = Gtk.ListStore(str, str, str, str, str)
        self.tree = Gtk.TreeView(model=self.store)
        for i, title in enumerate(("When", "State", "Device", "VID:PID", "Serial")):
            col = Gtk.TreeViewColumn(title, Gtk.CellRendererText(), text=i)
            col.set_resizable(True)
            col.set_sort_column_id(i)
            self.tree.append_column(col)
        scroll.add(self.tree)
        self.connect("delete-event", self.on_delete)
        self.reload()

    def on_delete(self, *_a):
        self.hide()
        return True

    def reload(self):
        self.store.clear()
        lines = read_attempts()
        blocked = 0
        for line in lines:
            p = parse_line(line)
            if p["state"] in ("soft-locked", "hard-locked", "locked"):
                blocked += 1
            ts = p["ts"]
            try:
                ts = datetime.fromisoformat(ts).strftime("%Y-%m-%d %H:%M:%S")
            except ValueError:
                pass
            self.store.append([ts, p["state"], p["product"], p["vidpid"], p["serial"]])
        total = len(lines)
        self.summary.set_text(
            f"{total} event(s)  ·  {blocked} while locked  ·  log: {attempt_log_path()}"
        )
        if total:
            self.tree.set_cursor(total - 1)

    def on_clear(self, *_a):
        dlg = Gtk.MessageDialog(
            transient_for=self,
            modal=True,
            message_type=Gtk.MessageType.QUESTION,
            buttons=Gtk.ButtonsType.OK_CANCEL,
            text="Clear the user attempt log?",
        )
        dlg.format_secondary_text(
            f"Clears {USER_LOG}. System log at {SYSTEM_LOG} is left alone."
        )
        resp = dlg.run()
        dlg.destroy()
        if resp != Gtk.ResponseType.OK:
            return
        DATA_DIR.mkdir(parents=True, exist_ok=True)
        USER_LOG.write_text("")
        self.reload()
        self.app.refresh_ui()


class PortlockApp:
    def __init__(self):
        DATA_DIR.mkdir(parents=True, exist_ok=True)
        CONFIG_DIR.mkdir(parents=True, exist_ok=True)
        if not USER_LOG.exists():
            USER_LOG.touch()
        if not CONFIG_PATH.exists():
            save_config(DEFAULT_CONFIG)

        self.cfg = load_config()
        self.state = get_state()
        self.session_locked = False
        self.last_log_count = count_attempts()
        self.last_notify_mtime = self._notify_mtime()
        self.attempt_win: AttemptWindow | None = None
        self._auto_busy = False

        icon = self._icon_path(self.state)
        self.indicator = AppIndicator3.Indicator.new(
            APP_ID, icon, AppIndicator3.IndicatorCategory.HARDWARE
        )
        self.indicator.set_status(AppIndicator3.IndicatorStatus.ACTIVE)
        self.indicator.set_title(f"GTDataworks {APP_NAME}")

        self.menu = Gtk.Menu()
        self.item_status = Gtk.MenuItem(label="")
        self.item_status.set_sensitive(False)
        self.menu.append(self.item_status)

        self.item_attempts = Gtk.MenuItem(label="")
        self.item_attempts.set_sensitive(False)
        self.menu.append(self.item_attempts)

        self.menu.append(Gtk.SeparatorMenuItem())

        self.item_auto = Gtk.CheckMenuItem(label="Auto-lock on lock screen")
        self.item_auto.set_active(bool(self.cfg.get("auto_lock", True)))
        self.item_auto.connect("toggled", self.on_auto_toggled)
        self.menu.append(self.item_auto)

        self.item_auto_unlock = Gtk.CheckMenuItem(
            label="Auto-unlock ports when session unlocks"
        )
        self.item_auto_unlock.set_active(
            bool(self.cfg.get("auto_unlock_on_session_unlock", True))
        )
        self.item_auto_unlock.connect("toggled", self.on_auto_unlock_toggled)
        self.menu.append(self.item_auto_unlock)

        self.menu.append(Gtk.SeparatorMenuItem())

        self.item_soft = Gtk.MenuItem(label="Soft lock (keep plugged sticks)…")
        self.item_soft.connect("activate", lambda *_: self.do_action("soft-lock", "manual"))
        self.menu.append(self.item_soft)

        self.item_hard = Gtk.MenuItem(label="Hard lock (block everything)…")
        self.item_hard.connect("activate", lambda *_: self.do_action("hard-lock", "manual"))
        self.menu.append(self.item_hard)

        self.item_unlock = Gtk.MenuItem(label="Unlock ports…")
        self.item_unlock.connect("activate", lambda *_: self.do_action("unlock"))
        self.menu.append(self.item_unlock)

        self.menu.append(Gtk.SeparatorMenuItem())

        item_view = Gtk.MenuItem(label="View attempt log…")
        item_view.connect("activate", self.on_view_log)
        self.menu.append(item_view)

        item_help = Gtk.MenuItem(label="How Auto-lock works…")
        item_help.connect("activate", self.on_help)
        self.menu.append(item_help)

        item_refresh = Gtk.MenuItem(label="Refresh status")
        item_refresh.connect("activate", lambda *_: self.refresh_ui())
        self.menu.append(item_refresh)

        self.menu.append(Gtk.SeparatorMenuItem())

        item_quit = Gtk.MenuItem(label="Quit")
        item_quit.connect("activate", lambda *_: Gtk.main_quit())
        self.menu.append(item_quit)

        self.menu.show_all()
        self.indicator.set_menu(self.menu)

        self.refresh_ui()
        self._setup_session_watchers()
        GLib.timeout_add(POLL_MS, self.on_poll)

    # --- icons / UI --------------------------------------------------------

    def _icon_path(self, state: str) -> str:
        name = (
            "portlock-unlocked.png"
            if state == "unlocked"
            else "portlock-locked.png"
        )
        path = ICON_DIR / name
        if path.is_file():
            return str(path)
        # legacy names
        alt = ICON_DIR / (
            "usb-unlocked.png" if state == "unlocked" else "usb-locked.png"
        )
        if alt.is_file():
            return str(alt)
        return "drive-removable-media" if state == "unlocked" else "security-high"

    def _notify_mtime(self) -> float:
        try:
            return NOTIFY_FLAG.stat().st_mtime
        except OSError:
            return 0.0

    def refresh_ui(self):
        self.state = get_state()
        total = count_attempts()
        blocked = count_blocked()
        reason = get_reason()

        self.item_status.set_label(f"Status: {state_label(self.state)}")
        extra = f"  · reason={reason}" if reason and reason != "none" else ""
        self.item_attempts.set_label(
            f"Attempts: {total} ({blocked} blocked){extra}"
        )

        self.item_soft.set_sensitive(self.state == "unlocked")
        self.item_hard.set_sensitive(self.state != "hard-locked")
        self.item_unlock.set_sensitive(self.state != "unlocked")

        short = {
            "unlocked": "OPEN",
            "soft-locked": "SOFT",
            "hard-locked": "HARD",
        }.get(self.state, "?")
        self.indicator.set_icon_full(
            self._icon_path(self.state), state_label(self.state)
        )
        self.indicator.set_label(f"PL:{short} ({total})", APP_NAME)

    def notify(self, title: str, body: str, critical: bool = False):
        urgency = "critical" if critical else "normal"
        try:
            subprocess.Popen(
                [
                    "notify-send",
                    f"--urgency={urgency}",
                    f"--app-name={APP_NAME}",
                    "--icon=drive-removable-media",
                    title,
                    body,
                ],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
        except OSError:
            pass

    def do_action(self, action: str, *extra: str):
        ok, msg = privileged(action, *extra)
        if not ok:
            self.notify(APP_NAME, f"Failed: {msg}", critical=True)
        else:
            GLib.timeout_add(350, self._post_action)
            return
        self.refresh_ui()

    def _post_action(self):
        self.refresh_ui()
        self.notify(APP_NAME, f"Ports are now {get_state()}.")
        return False

    def on_auto_toggled(self, item: Gtk.CheckMenuItem):
        self.cfg["auto_lock"] = bool(item.get_active())
        save_config(self.cfg)
        if self.cfg["auto_lock"]:
            self.notify(
                APP_NAME,
                "Auto-lock on. Screen lock → soft-lock (active sticks stay live).",
            )
        else:
            self.notify(APP_NAME, "Auto-lock off. Ports only change via this menu.")

    def on_auto_unlock_toggled(self, item: Gtk.CheckMenuItem):
        self.cfg["auto_unlock_on_session_unlock"] = bool(item.get_active())
        save_config(self.cfg)

    def on_view_log(self, *_a):
        if self.attempt_win is None:
            self.attempt_win = AttemptWindow(self)
        self.attempt_win.reload()
        self.attempt_win.present()

    def on_help(self, *_a):
        dlg = Gtk.MessageDialog(
            transient_for=None,
            modal=True,
            message_type=Gtk.MessageType.INFO,
            buttons=Gtk.ButtonsType.OK,
            text="How Auto-lock works",
        )
        dlg.format_secondary_text(
            "While Auto-lock is on:\n\n"
            "1. Unlock your session and plug a stick BEFORE locking the screen.\n"
            "2. When the lock screen appears, Portlock soft-locks:\n"
            "   • Already-plugged sticks stay active (writes finish safely).\n"
            "   • Any NEW stick is blocked and logged.\n"
            "3. If you unplug while locked, you cannot re-insert until unlock.\n"
            "4. Unlocking the session auto-unlocks ports (optional toggle).\n\n"
            "Hard lock (menu) blocks everything immediately — use when leaving\n"
            "the machine unattended. Manual hard-lock survives session unlock\n"
            "until you Unlock ports yourself.\n\n"
            "Not affiliated with the USBGuard project."
        )
        dlg.run()
        dlg.destroy()

    # --- session lock watchers ---------------------------------------------

    def _setup_session_watchers(self):
        """Listen for Cinnamon/GNOME screensaver + logind Lock/Unlock."""
        self._bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
        self._sys_bus = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)

        # Screensaver ActiveChanged on common buses
        for name in (
            "org.cinnamon.ScreenSaver",
            "org.gnome.ScreenSaver",
            "org.freedesktop.ScreenSaver",
            "org.mate.ScreenSaver",
        ):
            try:
                self._bus.signal_subscribe(
                    None,
                    name,
                    "ActiveChanged",
                    None,
                    None,
                    Gio.DBusSignalFlags.NONE,
                    self._on_screensaver_signal,
                    name,
                )
            except Exception:
                pass

        # Initial screensaver state (best effort)
        for name, path in (
            ("org.cinnamon.ScreenSaver", "/org/cinnamon/ScreenSaver"),
            ("org.gnome.ScreenSaver", "/org/gnome/ScreenSaver"),
            ("org.freedesktop.ScreenSaver", "/org/freedesktop/ScreenSaver"),
        ):
            try:
                proxy = Gio.DBusProxy.new_sync(
                    self._bus,
                    Gio.DBusProxyFlags.NONE,
                    None,
                    name,
                    path,
                    name,
                    None,
                )
                active = proxy.call_sync(
                    "GetActive", None, Gio.DBusCallFlags.NONE, 1000, None
                )
                if active and active.get_child_value(0).get_boolean():
                    self.session_locked = True
                break
            except Exception:
                continue

        # logind session Lock / Unlock
        try:
            self._sys_bus.signal_subscribe(
                "org.freedesktop.login1",
                "org.freedesktop.login1.Session",
                "Lock",
                None,
                None,
                Gio.DBusSignalFlags.NONE,
                self._on_logind_lock,
                True,
            )
            self._sys_bus.signal_subscribe(
                "org.freedesktop.login1",
                "org.freedesktop.login1.Session",
                "Unlock",
                None,
                None,
                Gio.DBusSignalFlags.NONE,
                self._on_logind_lock,
                False,
            )
        except Exception:
            pass

        if self.session_locked and self.cfg.get("auto_lock"):
            GLib.idle_add(self._apply_auto_soft_lock)

    def _on_screensaver_signal(
        self, _conn, _sender, _path, _iface, _signal, params, _user
    ):
        try:
            active = bool(params.unpack()[0])
        except Exception:
            return
        GLib.idle_add(self._handle_session_lock_change, active)

    def _on_logind_lock(
        self, _conn, _sender, _path, _iface, _signal, _params, locked
    ):
        GLib.idle_add(self._handle_session_lock_change, bool(locked))

    def _handle_session_lock_change(self, locked: bool):
        if locked == self.session_locked:
            return False
        self.session_locked = locked
        if not self.cfg.get("auto_lock"):
            return False
        if locked:
            self._apply_auto_soft_lock()
        elif self.cfg.get("auto_unlock_on_session_unlock", True):
            self._apply_auto_unlock()
        return False

    def _apply_auto_soft_lock(self):
        if self._auto_busy:
            return
        state = get_state()
        if state != "unlocked":
            # already soft or hard locked — leave alone
            return
        self._auto_busy = True

        def work():
            ok, msg = privileged("auto-soft-lock", auto=True)
            GLib.idle_add(self._auto_done, ok, msg, "soft-locked")
            return False

        GLib.timeout_add(50, work)

    def _apply_auto_unlock(self):
        if self._auto_busy:
            return
        state = get_state()
        reason = get_reason()
        if state == "unlocked":
            return
        if state == "hard-locked" and reason == "manual":
            if self.cfg.get("notify_on_auto", True):
                self.notify(
                    APP_NAME,
                    "Session unlocked, but manual hard-lock is still on.",
                )
            return
        self._auto_busy = True

        def work():
            ok, msg = privileged("auto-unlock", auto=True)
            GLib.idle_add(self._auto_done, ok, msg, "unlocked")
            return False

        GLib.timeout_add(50, work)

    def _auto_done(self, ok: bool, msg: str, expected: str):
        self._auto_busy = False
        self.refresh_ui()
        if not ok:
            # User cancelled polkit or error — don't spam forever
            self.notify(APP_NAME, f"Auto-lock action failed: {msg}", critical=True)
            return False
        if self.cfg.get("notify_on_auto", True):
            if expected == "soft-locked":
                self.notify(
                    APP_NAME,
                    "Screen locked → soft-lock. Active sticks kept; new ones blocked.",
                )
            else:
                self.notify(APP_NAME, "Session unlocked → ports open for new sticks.")
        return False

    def on_poll(self) -> bool:
        new_state = get_state()
        new_count = count_attempts()
        new_mtime = self._notify_mtime()

        if new_state != self.state or new_count != self.last_log_count:
            self.state = new_state
            self.refresh_ui()
            if self.attempt_win is not None and self.attempt_win.get_visible():
                self.attempt_win.reload()

        if new_mtime > self.last_notify_mtime and new_count > self.last_log_count:
            lines = read_attempts(limit=1)
            if lines:
                p = parse_line(lines[-1])
                if p["state"] in ("soft-locked", "hard-locked", "locked"):
                    self.notify(
                        "Portlock: blocked",
                        f"{p['product']} ({p['vidpid']})",
                        critical=True,
                    )
                else:
                    self.notify(
                        "Portlock: stick detected",
                        f"{p['product']} ({p['vidpid']})",
                    )

        self.last_log_count = new_count
        self.last_notify_mtime = new_mtime
        return True


def main() -> int:
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    lock_path = DATA_DIR / "tray.lock"
    lock_fd = open(lock_path, "w")
    try:
        import fcntl

        fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        print(f"{APP_NAME} is already running.", file=sys.stderr)
        return 0
    lock_fd.write(str(os.getpid()))
    lock_fd.flush()

    signal.signal(signal.SIGINT, signal.SIG_DFL)
    PortlockApp()
    Gtk.main()
    return 0


if __name__ == "__main__":
    sys.exit(main())
