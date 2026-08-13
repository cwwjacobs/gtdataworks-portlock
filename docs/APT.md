# Apt repository

Portlock ships a **static apt repository** on GitHub Pages:

**https://cwwjacobs.github.io/gtdataworks-portlock/**

## For users

```bash
# product page: https://gtdataworks.com/portlock/
curl -fsSL https://gtdataworks.com/portlock/install-apt.sh | sudo bash
# forgot sudo? the script goat-modes and re-runs elevated
# curl -fsSL https://gtdataworks.com/portlock/install-apt.sh | bash
sudo apt update
sudo apt install gtdataworks-portlock
portlock
```

Upgrade later:

```bash
sudo apt update && sudo apt install --only-upgrade gtdataworks-portlock
```

Remove repo + package:

```bash
sudo apt remove gtdataworks-portlock
sudo rm -f /etc/apt/sources.list.d/gtdataworks-portlock.list
sudo apt update
```

## For maintainers

1. Bump `VERSION`, update changelog.
2. `make deb` → `dist/gtdataworks-portlock_X.Y.Z_all.deb`
3. `make apt-repo` → `packaging/apt-repo/`
4. Tag + GitHub Release (attach `.deb`).
5. Push/publish `gh-pages` with repo contents (CI does this on release).

### Mandatory GPG signing

Signed `InRelease` metadata is required. There is no `trusted=yes` fallback.

```bash
# packaging/apt-signing.conf pins the real 40-hex fingerprint of the
# Portlock APT signing key. CI secrets:
#   APT_GPG_PRIVATE_KEY          (armored private key)
#   PORTLOCK_APT_FINGERPRINT     (same 40-hex pin as apt-signing.conf)
#
# Local rebuild (private key never in the repo):
export GPG_PRIVATE_KEY="$(cat ~/.config/gtdataworks/keys/portlock-apt-private.asc)"
export PORTLOCK_APT_FINGERPRINT="$(tr -d ' \n' < ~/.config/gtdataworks/keys/portlock-apt-fingerprint.txt)"
./packaging/build-apt-repo.sh
# Publishes KEY.gpg + InRelease + Release.gpg
# Fails closed if the fingerprint is unset/invalid or InRelease is missing.
```

### Layout

```
dists/stable/main/binary-all/Packages.gz
dists/stable/Release
pool/main/g/gtdataworks-portlock/*.deb
install-apt.sh
index.html
KEY.gpg          # required (signed repo)
```
