# Auto-lock design

## Goals

1. Locking the screen must not interrupt an in-progress write to a thumb drive.
2. While the screen is locked, nobody should be able to introduce a *new* mass-storage device.
3. If a preserved stick is removed while locked, it cannot come back until ports open.
4. Auto transitions must not prompt for a password every time (usability).

## States

| State | Block udev rule | Active sticks |
|-------|-----------------|---------------|
| `unlocked` | absent (`.disabled`) | authorized |
| `soft-locked` | present | left as-is (write-safe) |
| `hard-locked` | present | deauthorized |

`reason` is `auto`, `manual`, `install`, `migrated`, or `none`.

## Transitions

```
unlocked  --screen lock + auto_lock-->  soft-locked (reason=auto)
soft-locked (reason=auto) --session unlock + auto_unlock--> unlocked
unlocked  --menu Soft lock--> soft-locked (reason=manual)
unlocked  --menu Hard lock--> hard-locked (reason=manual)
*         --menu Unlock--> unlocked
hard-locked (any reason) --session unlock--> hard-locked (kept)
soft-locked (reason≠auto) --session unlock--> soft-locked (kept)
```

`auto_unlock` may reverse **only** `state=soft-locked` with `reason=auto`.
Every hard-lock (manual, install, migrated, or other) is sticky until an
authenticated/manual unlock.

## Why soft-lock does not deauthorize

Writing `0` to `authorized` on a live mass-storage interface can tear down the
SCSI device under a mounted filesystem. Soft-lock only ensures the udev rule
is active for *future* `add` events of interface class `08`.

## Passwordless auto path

`portlock-ctl-auto` only accepts `auto-soft-lock` and `auto-unlock`.
Polkit action `com.gtdataworks.portlock.auto` allows the active local user
without authentication. Manual hard-lock still uses `auth_admin_keep`.
