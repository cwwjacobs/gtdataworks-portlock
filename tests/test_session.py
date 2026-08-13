#!/usr/bin/env python3
"""Unit tests for session-path encoding and auto-unlock policy (no gi import)."""

from __future__ import annotations

import ast
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = (ROOT / "app" / "portlock.py").read_text(encoding="utf-8")


def load_helpers() -> dict:
    tree = ast.parse(SRC, filename="app/portlock.py")
    wanted = {"logind_session_object_path", "may_auto_unlock"}
    keep = [
        node
        for node in tree.body
        if isinstance(node, ast.FunctionDef) and node.name in wanted
    ]
    if {n.name for n in keep} != wanted:
        raise SystemExit(f"missing helpers: wanted {wanted}, got {[n.name for n in keep]}")
    mod = ast.Module(body=keep, type_ignores=[])
    ns: dict = {}
    exec(compile(mod, "app/portlock.py", "exec"), ns)
    return ns


def main() -> int:
    ns = load_helpers()
    path_fn = ns["logind_session_object_path"]
    may = ns["may_auto_unlock"]
    failed = 0

    def check(name: str, cond: bool) -> None:
        nonlocal failed
        if cond:
            print(f"PASS  {name}")
        else:
            failed += 1
            print(f"FAIL  {name}")

    check("session path c2", path_fn("c2") == "/org/freedesktop/login1/session/c2")
    check("session path 3", path_fn("3") == "/org/freedesktop/login1/session/_3")
    check("session path 32", path_fn("32") == "/org/freedesktop/login1/session/_32")
    check("session path empty", path_fn("") is None)
    check("session path none", path_fn(None) is None)
    check("session path slash", path_fn("foo/bar") is None)
    check("session path dotdot", path_fn("../evil") is None)
    check("session path dots", path_fn("c2.evil") is None)

    check("auto unlock soft+auto", may("soft-locked", "auto") is True)
    check("no auto unlock hard+auto", may("hard-locked", "auto") is False)
    check("no auto unlock hard+manual", may("hard-locked", "manual") is False)
    check("no auto unlock hard+install", may("hard-locked", "install") is False)
    check("no auto unlock hard+migrated", may("hard-locked", "migrated") is False)
    check("no auto unlock soft+manual", may("soft-locked", "manual") is False)
    check("no auto unlock unlocked", may("unlocked", "auto") is False)

    check("source uses XDG_SESSION_ID", "XDG_SESSION_ID" in SRC)
    check("source calls GetSession", '"GetSession"' in SRC or "'GetSession'" in SRC)
    check("source reads LockedHint", "LockedHint" in SRC)
    check("source reconciles lock", "_reconcile_session_lock" in SRC)
    check(
        "logind Lock subscribe is per-session",
        "self._session_path" in SRC
        and 'signal_subscribe(\n                    "org.freedesktop.login1"' in SRC,
    )
    # Must not subscribe to every session (object_path=None) for Lock.
    lock_block = SRC.split("if self._session_path:", 1)
    check("logind subscribe gated on this session path", len(lock_block) == 2)
    if len(lock_block) == 2:
        chunk = lock_block[1].split("def ", 1)[0]
        check(
            "logind Lock path is session object not None",
            "self._session_path" in chunk and '"Lock"' in chunk,
        )

    return failed


if __name__ == "__main__":
    sys.exit(main())
