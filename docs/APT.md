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

### Optional GPG signing

```bash
# Generate a CI signing key (no passphrase), export, store as secret:
#   gh secret set APT_GPG_PRIVATE_KEY < private.asc
export GPG_PRIVATE_KEY="$(cat private.asc)"
./packaging/build-apt-repo.sh
# Publishes KEY.gpg + InRelease + Release.gpg
```

Without a key, `install-apt.sh` uses `trusted=yes` (fine for early product; add signing when you want stricter trust).

### Layout

```
dists/stable/main/binary-all/Packages.gz
dists/stable/Release
pool/main/g/gtdataworks-portlock/*.deb
install-apt.sh
index.html
KEY.gpg          # if signed
```
