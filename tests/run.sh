#!/bin/bash
# Focused hardening regression tests. No sudo, no live USB, no package install.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PASS=0
FAIL=0
SKIP=0

pass() { PASS=$((PASS + 1)); printf 'PASS  %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL  %s\n' "$1"; }
skip() { SKIP=$((SKIP + 1)); printf 'SKIP  %s\n' "$1"; }

assert_ok() {
  local name="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    pass "$name"
  else
    fail "$name"
  fi
}

assert_fail() {
  local name="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    fail "$name"
  else
    pass "$name"
  fi
}

contains() {
  local file="$1" pat="$2"
  grep -qE "$pat" "$file"
}

# ---------------------------------------------------------------------------
# Static: root helpers never write under user homes
# ---------------------------------------------------------------------------
if grep -nE 'source[[:space:]]+"?\$CONFIG' sbin/portlock-attempt-logger >/dev/null; then
  fail "logger does not source notify-user.conf"
else
  pass "logger does not source notify-user.conf"
fi

if grep -nE 'chown[[:space:]]|mkdir -p "\$home|\$home/\.local/share|mirror_to_users' sbin/portlock-attempt-logger >/dev/null; then
  fail "logger has no home mkdir/write/chown primitive"
else
  pass "logger has no home mkdir/write/chown primitive"
fi

if grep -n 'parse_notify_user' sbin/portlock-attempt-logger >/dev/null; then
  pass "logger parses NOTIFY_USER safely"
else
  fail "logger parses NOTIFY_USER safely"
fi

if grep -nE 'install -d "\$USER_HOME|cat > "\$USER_HOME|touch "\$USER_HOME' install.sh >/dev/null; then
  fail "install.sh has no root redirects into USER_HOME"
else
  pass "install.sh has no root redirects into USER_HOME"
fi

if grep -nE '^chown |chown -R "\$USER_NAME' install.sh >/dev/null; then
  fail "install.sh does not chown user-home paths as root"
else
  pass "install.sh does not chown user-home paths as root"
fi

if grep -n 'as_install_user' install.sh >/dev/null; then
  pass "install.sh creates remaining user artifacts as the user"
else
  fail "install.sh creates remaining user artifacts as the user"
fi

if grep -n '/etc/xdg/autostart' install.sh >/dev/null; then
  pass "install.sh installs system XDG autostart"
else
  fail "install.sh installs system XDG autostart"
fi

# ---------------------------------------------------------------------------
# Static: auto-unlock never clears hard-lock
# ---------------------------------------------------------------------------
if grep -A20 '^auto_unlock()' sbin/portlock-ctl | grep -q 'soft-locked'; then
  pass "auto_unlock is gated on soft-locked"
else
  fail "auto_unlock is gated on soft-locked"
fi

if grep -A20 '^auto_unlock()' sbin/portlock-ctl | grep -q 'reason=auto\|"auto"'; then
  pass "auto_unlock requires reason=auto"
else
  fail "auto_unlock requires reason=auto"
fi

# The only unlock() call in auto_unlock must sit inside the soft-locked+auto branch.
if awk '
  /^auto_unlock\(\)/ {infn=1}
  infn && /^[a-z_].*\(\)/ && !/^auto_unlock\(\)/ {infn=0}
  infn && /unlock$/ {print}
' sbin/portlock-ctl | grep -q unlock; then
  # confirm it is not an unguarded trailing unlock
  if awk '
    /^auto_unlock\(\)/ {infn=1; next}
    infn && /^[a-z_].*\(\) \{/ {infn=0}
    infn {body=body $0 "\n"}
    END {print body}
  ' sbin/portlock-ctl | grep -q 'soft-locked'; then
    pass "auto_unlock body still contains unlock() only after soft-locked check"
  else
    fail "auto_unlock body still contains unlock() only after soft-locked check"
  fi
else
  fail "auto_unlock still has a conditional unlock() path"
fi

# ---------------------------------------------------------------------------
# Static: snapshot resolves real device parent; hard-lock snapshots first
# ---------------------------------------------------------------------------
if grep -n 'readlink -f' sbin/portlock-ctl >/dev/null; then
  pass "portlock-ctl resolves sysfs via readlink -f"
else
  fail "portlock-ctl resolves sysfs via readlink -f"
fi

if awk '
  /^hard_lock\(\)/ {infn=1}
  infn && /^[a-z_].*\(\) \{/ && !/^hard_lock\(\)/ {infn=0}
  infn {print NR":"$0}
' sbin/portlock-ctl | awk '
  /snapshot_active_ms/ {s=NR}
  /deauthorize_all_ms/ {d=NR}
  END {exit !(s && d && s<d)}
'; then
  pass "hard_lock snapshots before deauthorize"
else
  fail "hard_lock snapshots before deauthorize"
fi

if grep -n 'idVendor' sbin/portlock-ctl >/dev/null \
   && grep -n 'bInterfaceClass' sbin/portlock-ctl >/dev/null; then
  pass "snapshot validates expected sysfs attributes"
else
  fail "snapshot validates expected sysfs attributes"
fi

# preserved file is not consulted by unlock/authorize
if awk '
  /^unlock\(\)/ {infn=1}
  infn && /^[a-z_].*\(\) \{/ && !/^unlock\(\)/ {infn=0}
  infn && /preserved-at-lock/ {bad=1}
  END {exit bad}
' sbin/portlock-ctl; then
  pass "unlock does not treat snapshot as an allowlist"
else
  fail "unlock does not treat snapshot as an allowlist"
fi

# ---------------------------------------------------------------------------
# Static: APT trust
# ---------------------------------------------------------------------------
if grep -nE 'trusted=yes' packaging/install-apt.sh website/portlock/install-apt.sh packaging/build-apt-repo.sh \
     | grep -vE 'no trusted=yes|not .*trusted=yes' >/dev/null; then
  fail "apt scripts contain no trusted=yes path"
else
  pass "apt scripts contain no trusted=yes path"
fi

if grep -n 'signed-by' packaging/install-apt.sh >/dev/null; then
  pass "install-apt.sh uses signed-by"
else
  fail "install-apt.sh uses signed-by"
fi

if grep -n 'mktemp' packaging/install-apt.sh >/dev/null; then
  pass "install-apt.sh fetches the key via mktemp"
else
  fail "install-apt.sh fetches the key via mktemp"
fi

PINNED_FPR="$(awk -F= '/^[[:space:]]*PORTLOCK_APT_FINGERPRINT=/ {
  v=$2; gsub(/[[:space:]\"'\'']/, "", v); print toupper(v); exit
}' packaging/apt-signing.conf)"
DEFAULT_FPR="$(sed -n 's/^DEFAULT_PORTLOCK_APT_FINGERPRINT="\([0-9A-Fa-f]\{40\}\)".*/\U\1/p' packaging/install-apt.sh | head -1)"
if [[ "$PINNED_FPR" =~ ^[0-9A-F]{40}$ ]] \
   && [[ "$DEFAULT_FPR" == "$PINNED_FPR" ]] \
   && grep -n 'is_pinned_fingerprint' packaging/install-apt.sh >/dev/null \
   && ! grep -n 'REPLACE_WITH_REPO_SIGNING_FINGERPRINT' packaging/install-apt.sh packaging/apt-signing.conf website/portlock/install-apt.sh >/dev/null; then
  pass "apt installer pins a real 40-hex fingerprint"
else
  fail "apt installer pins a real 40-hex fingerprint"
fi

if grep -n 'InRelease' packaging/build-apt-repo.sh >/dev/null \
   && grep -n 'refusing to ship' packaging/build-apt-repo.sh >/dev/null; then
  pass "repo build fails closed without InRelease"
else
  fail "repo build fails closed without InRelease"
fi

# ---------------------------------------------------------------------------
# Static: fresh hard-lock invokes deauthorize helper
# ---------------------------------------------------------------------------
if grep -n 'portlock-ctl hard-lock' install.sh >/dev/null; then
  pass "source install invokes portlock-ctl hard-lock"
else
  fail "source install invokes portlock-ctl hard-lock"
fi

if grep -n 'portlock-ctl hard-lock' packaging/build-deb.sh >/dev/null; then
  pass "deb postinst invokes portlock-ctl hard-lock"
else
  fail "deb postinst invokes portlock-ctl hard-lock"
fi

if grep -n 'etc/xdg/autostart' packaging/build-deb.sh >/dev/null; then
  pass "deb build stages /etc/xdg/autostart desktop entry"
else
  fail "deb build stages /etc/xdg/autostart desktop entry"
fi

# Restricted two-binary polkit architecture preserved
if grep -q 'portlock-ctl-auto only allows auto-soft-lock | auto-unlock' sbin/portlock-ctl-auto \
   && grep -q 'org.freedesktop.policykit.exec.path">/usr/local/sbin/portlock-ctl-auto' polkit/com.gtdataworks.portlock.auto.policy \
   && grep -q 'auth_admin_keep' polkit/com.gtdataworks.portlock.policy; then
  pass "restricted two-binary polkit architecture preserved"
else
  fail "restricted two-binary polkit architecture preserved"
fi

# ---------------------------------------------------------------------------
# Behavioral: parse_notify_user (no shell execution of config)
# ---------------------------------------------------------------------------
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# shellcheck disable=SC1091
PORTLOCK_LOGGER_LIB_ONLY=1 source "$ROOT/sbin/portlock-attempt-logger"

mal="$TMP/notify-evil.conf"
cat > "$mal" <<EOF
# comment
NOTIFY_USER="\$(echo pwned > '$TMP/pwned-source')"
touch '$TMP/pwned-source2'
evil() { echo hi; }
NOTIFY_USER=alice
EOF
NOTIFY_USER=""
parse_notify_user "$mal"
if [[ "$NOTIFY_USER" == "alice" && ! -e "$TMP/pwned-source" && ! -e "$TMP/pwned-source2" ]]; then
  pass "notify-user.conf parser ignores shell metacharacters"
else
  fail "notify-user.conf parser ignores shell metacharacters (got NOTIFY_USER='${NOTIFY_USER:-}')"
fi

quoted="$TMP/notify-quoted.conf"
printf 'NOTIFY_USER="bob"\n' > "$quoted"
NOTIFY_USER=""
parse_notify_user "$quoted"
if [[ "$NOTIFY_USER" == "bob" ]]; then
  pass "notify-user.conf parser accepts quoted username"
else
  fail "notify-user.conf parser accepts quoted username"
fi

bad="$TMP/notify-bad.conf"
printf 'NOTIFY_USER=../evil\nNOTIFY_USER=root;id\n' > "$bad"
NOTIFY_USER="preset"
parse_notify_user "$bad"
if [[ -z "$NOTIFY_USER" ]]; then
  pass "notify-user.conf parser rejects unsafe usernames"
else
  fail "notify-user.conf parser rejects unsafe usernames"
fi

# ---------------------------------------------------------------------------
# Behavioral: logger run does not write under a planted home
# ---------------------------------------------------------------------------
LDIR="$TMP/logger-run"
mkdir -p "$LDIR/bin" "$LDIR/home/alice" "$LDIR/var/log" "$LDIR/run" "$LDIR/etc"
printf 'NOTIFY_USER=alice\n' > "$LDIR/etc/notify-user.conf"
echo unlocked > "$LDIR/state"
cat > "$LDIR/bin/who" <<'EOF'
#!/bin/bash
echo alice
EOF
cat > "$LDIR/bin/logger" <<'EOF'
#!/bin/bash
exit 0
EOF
cat > "$LDIR/bin/runuser" <<EOF
#!/bin/bash
echo runuser "\$*" >> "$LDIR/runuser.log"
exit 0
EOF
cat > "$LDIR/bin/id" <<'EOF'
#!/bin/bash
if [[ "$1" == "-u" ]]; then echo 1000; exit 0; fi
command -p id "$@"
EOF
chmod +x "$LDIR/bin"/*

python3 - <<PY
from pathlib import Path
src = Path("sbin/portlock-attempt-logger").read_text()
td = Path("$LDIR")
repl = {
    'LOG="/var/log/portlock-attempts.log"': f'LOG="{td}/var/log/portlock-attempts.log"',
    'STATE_FILE="/var/lib/gtdataworks-portlock/state"': f'STATE_FILE="{td}/state"',
    'LOCK_FILE="/run/portlock-attempt-logger.lock"': f'LOCK_FILE="{td}/run/logger.lock"',
    'CONFIG="/etc/gtdataworks-portlock/notify-user.conf"': f'CONFIG="{td}/etc/notify-user.conf"',
}
for a,b in repl.items():
    if a not in src:
        raise SystemExit(f"logger rewrite missed {a!r}")
    src = src.replace(a, b, 1)
src = src.replace('[[ "${PORTLOCK_LOGGER_LIB_ONLY:-0}" == 1 ]]', '[[ 0 == 1 ]]', 1)
(td / "logger").write_text(src)
PY
chmod +x "$LDIR/logger"
HOME="$LDIR/home/alice" PATH="$LDIR/bin:$PATH" "$LDIR/logger" || true

if [[ -f "$LDIR/var/log/portlock-attempts.log" ]]; then
  pass "logger still writes the system attempt log"
else
  fail "logger still writes the system attempt log"
fi

if [[ ! -e "$LDIR/home/alice/.local" ]]; then
  pass "logger did not create files under a planted home"
else
  fail "logger did not create files under a planted home"
fi

# ---------------------------------------------------------------------------
# Behavioral: auto_unlock + snapshot via rewritten portlock-ctl
# ---------------------------------------------------------------------------
CTL_DIR="$TMP/ctl"
mkdir -p "$CTL_DIR/var/lib/gtdataworks-portlock" \
         "$CTL_DIR/etc/udev/rules.d" \
         "$CTL_DIR/usr/local/share/gtdataworks-portlock" \
         "$CTL_DIR/var/log" \
         "$CTL_DIR/bin" \
         "$CTL_DIR/sys/devices/pci0000:00/usb1/1-2/1-2:1.0" \
         "$CTL_DIR/sys/bus/usb/devices"
cp "$ROOT/udev/99-portlock-block-ms.rules" \
   "$CTL_DIR/usr/local/share/gtdataworks-portlock/"
cat > "$CTL_DIR/bin/udevadm" <<'EOF'
#!/bin/bash
exit 0
EOF
cat > "$CTL_DIR/bin/logger" <<'EOF'
#!/bin/bash
exit 0
EOF
chmod +x "$CTL_DIR/bin/udevadm" "$CTL_DIR/bin/logger"

python3 - "$CTL_DIR" <<'PY'
import sys
from pathlib import Path
src = Path("sbin/portlock-ctl").read_text()
td = Path(sys.argv[1])
repls = [
    ('RULE="/etc/udev/rules.d/99-portlock-block-ms.rules"', f'RULE="{td}/etc/udev/rules.d/99-portlock-block-ms.rules"'),
    ('RULE_DISABLED="/etc/udev/rules.d/99-portlock-block-ms.rules.disabled"', f'RULE_DISABLED="{td}/etc/udev/rules.d/99-portlock-block-ms.rules.disabled"'),
    ('LEGACY_RULE="/etc/udev/rules.d/99-block-usb-mass-storage.rules"', f'LEGACY_RULE="{td}/etc/udev/rules.d/99-block-usb-mass-storage.rules"'),
    ('LEGACY_RULE_DISABLED="/etc/udev/rules.d/99-block-usb-mass-storage.rules.disabled"', f'LEGACY_RULE_DISABLED="{td}/etc/udev/rules.d/99-block-usb-mass-storage.rules.disabled"'),
    ('RULE_TEMPLATE="/usr/local/share/gtdataworks-portlock/99-portlock-block-ms.rules"', f'RULE_TEMPLATE="{td}/usr/local/share/gtdataworks-portlock/99-portlock-block-ms.rules"'),
    ('STATE_DIR="/var/lib/gtdataworks-portlock"', f'STATE_DIR="{td}/var/lib/gtdataworks-portlock"'),
    ('ATTEMPT_LOG="/var/log/portlock-attempts.log"', f'ATTEMPT_LOG="{td}/var/log/portlock-attempts.log"'),
    ('/sys/bus/usb/devices', f'{td}/sys/bus/usb/devices'),
]
for a,b in repls:
    if a not in src:
        raise SystemExit(f"ctl rewrite missed {a!r}")
    src = src.replace(a, b)
old = (
    "ensure_root() {\n"
    "  if [[ ${EUID:-$(id -u)} -ne 0 ]]; then\n"
    '    echo "error: must run as root (use pkexec)" >&2\n'
    "    exit 1\n"
    "  fi\n"
    "}"
)
new = "ensure_root() {\n  return 0\n}"
if old not in src:
    raise SystemExit("ctl rewrite missed ensure_root")
src = src.replace(old, new)
(td / "portlock-ctl").write_text(src)
PY
chmod +x "$CTL_DIR/portlock-ctl"
HARNESS=(env PATH="$CTL_DIR/bin:$PATH" "$CTL_DIR/portlock-ctl")

write_state() {
  printf '%s' "$1" > "$CTL_DIR/var/lib/gtdataworks-portlock/state"
  printf '%s' "$2" > "$CTL_DIR/var/lib/gtdataworks-portlock/reason"
}

# seed an enabled rule so unlock/disable has something to move
cp "$ROOT/udev/99-portlock-block-ms.rules" \
   "$CTL_DIR/etc/udev/rules.d/99-portlock-block-ms.rules"

for pair in "hard-locked:manual" "hard-locked:install" "hard-locked:migrated" "hard-locked:other"; do
  s="${pair%%:*}"
  r="${pair##*:}"
  write_state "$s" "$r"
  out="$("${HARNESS[@]}" auto-unlock 2>/dev/null || true)"
  got="$(tr -d '\n' < "$CTL_DIR/var/lib/gtdataworks-portlock/state")"
  if [[ "$got" == "hard-locked" && "$out" == *hard-locked* ]]; then
    pass "auto-unlock keeps ${s}/${r}"
  else
    fail "auto-unlock keeps ${s}/${r} (state=${got} out=${out})"
  fi
done

write_state "soft-locked" "manual"
"${HARNESS[@]}" auto-unlock >/dev/null 2>&1 || true
got="$(tr -d '\n' < "$CTL_DIR/var/lib/gtdataworks-portlock/state")"
if [[ "$got" == "soft-locked" ]]; then
  pass "auto-unlock keeps manual soft-lock"
else
  fail "auto-unlock keeps manual soft-lock (state=${got})"
fi

write_state "soft-locked" "auto"
cp "$ROOT/udev/99-portlock-block-ms.rules" \
   "$CTL_DIR/etc/udev/rules.d/99-portlock-block-ms.rules"
"${HARNESS[@]}" auto-unlock >/dev/null 2>&1 || true
got="$(tr -d '\n' < "$CTL_DIR/var/lib/gtdataworks-portlock/state")"
if [[ "$got" == "unlocked" ]]; then
  pass "auto-unlock reverses soft-locked/auto"
else
  fail "auto-unlock reverses soft-locked/auto (state=${got})"
fi

# Fake sysfs: bus path is a symlink; parent attrs live on the real device.
printf '1234' > "$CTL_DIR/sys/devices/pci0000:00/usb1/1-2/idVendor"
printf '5678' > "$CTL_DIR/sys/devices/pci0000:00/usb1/1-2/idProduct"
printf 'ABC' > "$CTL_DIR/sys/devices/pci0000:00/usb1/1-2/serial"
printf 'FakeStick' > "$CTL_DIR/sys/devices/pci0000:00/usb1/1-2/product"
printf '08' > "$CTL_DIR/sys/devices/pci0000:00/usb1/1-2/1-2:1.0/bInterfaceClass"
printf '1' > "$CTL_DIR/sys/devices/pci0000:00/usb1/1-2/1-2:1.0/authorized"
ln -sfn ../../../devices/pci0000:00/usb1/1-2/1-2:1.0 \
  "$CTL_DIR/sys/bus/usb/devices/1-2:1.0"

# Start unlocked so hard-lock runs fully.
write_state "unlocked" "none"
rm -f "$CTL_DIR/etc/udev/rules.d/99-portlock-block-ms.rules"
cp "$ROOT/udev/99-portlock-block-ms.rules" \
   "$CTL_DIR/etc/udev/rules.d/99-portlock-block-ms.rules.disabled"
"${HARNESS[@]}" hard-lock install >/dev/null 2>&1 || true
snap="$CTL_DIR/var/lib/gtdataworks-portlock/preserved-at-lock.txt"
auth="$(tr -d '\n' < "$CTL_DIR/sys/devices/pci0000:00/usb1/1-2/1-2:1.0/authorized")"
if [[ -f "$snap" ]] && grep -q 'vid=1234' "$snap" && grep -q 'pid=5678' "$snap"; then
  pass "snapshot resolves real device parent through interface symlink"
else
  fail "snapshot resolves real device parent through interface symlink ($(cat "$snap" 2>/dev/null || true))"
fi
if [[ "$auth" == "0" ]]; then
  pass "hard-lock deauthorizes attached class-08 interface"
else
  fail "hard-lock deauthorizes attached class-08 interface (authorized=${auth})"
fi
if grep -q 'vid=1234' "$snap" && [[ "$auth" == "0" ]]; then
  pass "snapshot captured the device before deauthorization"
else
  fail "snapshot captured the device before deauthorization"
fi

# ---------------------------------------------------------------------------
# Behavioral: apt fingerprint helpers + fail-closed repo build
# ---------------------------------------------------------------------------
# shellcheck disable=SC1091
PORTLOCK_APT_LIB_ONLY=1 source "$ROOT/packaging/install-apt.sh"

EXPECTED_FINGERPRINT="REPLACE_WITH_REPO_SIGNING_FINGERPRINT"
if require_pinned_fingerprint >/dev/null 2>&1; then
  fail "placeholder fingerprint is rejected"
else
  pass "placeholder fingerprint is rejected"
fi

EXPECTED_FINGERPRINT="0123456789ABCDEF0123456789ABCDEF01234567"
if require_pinned_fingerprint >/dev/null 2>&1; then
  pass "40-hex fingerprint is accepted"
else
  fail "40-hex fingerprint is accepted"
fi

EXPECTED_FINGERPRINT="not-a-fingerprint"
if require_pinned_fingerprint >/dev/null 2>&1; then
  fail "non-hex fingerprint is rejected"
else
  pass "non-hex fingerprint is rejected"
fi

if [[ -x "$ROOT/packaging/build-apt-repo.sh" ]]; then
  if PORTLOCK_APT_FINGERPRINT="" "$ROOT/packaging/build-apt-repo.sh" >/dev/null 2>"$TMP/repo-err"; then
    fail "unsigned/unpinned repo build fails closed"
  else
    if grep -qi 'fingerprint\|cannot proceed\|not allowed\|unsigned' "$TMP/repo-err"; then
      pass "unsigned/unpinned repo build fails closed"
    else
      fail "unsigned/unpinned repo build fails closed (unexpected stderr)"
    fi
  fi
fi

# ---------------------------------------------------------------------------
# Python helpers + compile
# ---------------------------------------------------------------------------
if python3 -m py_compile "$ROOT/app/portlock.py"; then
  pass "python3 -m py_compile app/portlock.py"
else
  fail "python3 -m py_compile app/portlock.py"
fi

py_rc=0
py_out="$(python3 "$ROOT/tests/test_session.py" || py_rc=$?)"
printf '%s\n' "$py_out"
py_fail=$(printf '%s\n' "$py_out" | grep -c '^FAIL' || true)
py_pass=$(printf '%s\n' "$py_out" | grep -c '^PASS' || true)
PASS=$((PASS + py_pass))
FAIL=$((FAIL + py_fail))
if [[ "$py_rc" -ne 0 && "$py_fail" -eq 0 ]]; then
  fail "tests/test_session.py exited ${py_rc}"
fi

# ---------------------------------------------------------------------------
# Package build (non-installing)
# ---------------------------------------------------------------------------
if command -v dpkg-deb >/dev/null 2>&1; then
  if "$ROOT/packaging/build-deb.sh" >"$TMP/deb-build.out" 2>&1; then
    pass "packaging/build-deb.sh"
    DEB="$(ls -1 "$ROOT/dist"/gtdataworks-portlock_*.deb 2>/dev/null | tail -1)"
    if [[ -n "$DEB" ]]; then
      dpkg-deb -c "$DEB" > "$TMP/deb-list"
    else
      : > "$TMP/deb-list"
    fi
    if grep -q 'etc/xdg/autostart/gtdataworks-portlock.desktop' "$TMP/deb-list"; then
      pass "deb contains /etc/xdg/autostart desktop entry"
    else
      fail "deb contains /etc/xdg/autostart desktop entry"
    fi
    if grep -q 'usr/share/applications/gtdataworks-portlock.desktop' "$TMP/deb-list"; then
      pass "deb still contains the normal applications launcher"
    else
      fail "deb still contains the normal applications launcher"
    fi
    mkdir -p "$TMP/deb-ctrl"
    dpkg-deb -e "$DEB" "$TMP/deb-ctrl"
    if grep -q 'portlock-ctl hard-lock' "$TMP/deb-ctrl/postinst"; then
      pass "built postinst invokes deauthorization via hard-lock"
    else
      fail "built postinst invokes deauthorization via hard-lock"
    fi
  else
    fail "packaging/build-deb.sh"
    sed -n '1,40p' "$TMP/deb-build.out" >&2 || true
  fi
else
  skip "dpkg-deb not available; skipped .deb contents checks"
fi

# Optional: signed repo happy path with a throwaway key (no install).
if command -v apt-ftparchive >/dev/null 2>&1 && command -v gpg >/dev/null 2>&1 \
   && ls "$ROOT/dist"/gtdataworks-portlock_*.deb >/dev/null 2>&1; then
  GNUPGHOME="$TMP/gnupg"
  mkdir -p "$GNUPGHOME"
  chmod 700 "$GNUPGHOME"
  export GNUPGHOME
  if gpg --batch --pinentry-mode loopback --passphrase '' \
       --quick-generate-key 'Portlock CI Test <portlock-test@example.invalid>' \
       default default never >/dev/null 2>&1; then
    FPR="$(gpg --list-secret-keys --with-colons | awk -F: '/^fpr:/ {print $10; exit}')"
    KEY="$(gpg --batch --armor --export-secret-keys "$FPR")"
    if APT_REPO_OUT="$TMP/apt-repo" PORTLOCK_APT_FINGERPRINT="$FPR" \
         GPG_PRIVATE_KEY="$KEY" "$ROOT/packaging/build-apt-repo.sh" \
         >"$TMP/apt-ok.out" 2>"$TMP/apt-ok.err"; then
      if [[ -s "$TMP/apt-repo/dists/stable/InRelease" && -s "$TMP/apt-repo/KEY.gpg" ]]; then
        pass "signed repo build produces InRelease when fingerprint is pinned"
      else
        fail "signed repo build produces InRelease when fingerprint is pinned"
      fi
    else
      fail "signed repo build produces InRelease when fingerprint is pinned"
      sed -n '1,40p' "$TMP/apt-ok.err" >&2 || true
    fi
    # Wrong fingerprint must not ship
    if APT_REPO_OUT="$TMP/apt-repo-bad" PORTLOCK_APT_FINGERPRINT="0123456789ABCDEF0123456789ABCDEF01234567" \
         GPG_PRIVATE_KEY="$KEY" "$ROOT/packaging/build-apt-repo.sh" \
         >/dev/null 2>"$TMP/apt-bad.err"; then
      fail "repo build rejects fingerprint mismatch"
    else
      pass "repo build rejects fingerprint mismatch"
    fi
  else
    skip "could not generate a temporary GPG key"
  fi
  unset GNUPGHOME
else
  skip "apt-ftparchive/gpg/deb missing; skipped signed-repo happy path"
fi

# ---------------------------------------------------------------------------
echo
echo "---"
echo "${PASS} passed, ${FAIL} failed, ${SKIP} skipped"
if [[ "$FAIL" -ne 0 ]]; then
  exit 1
fi
exit 0
