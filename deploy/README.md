# Komga / rclone VFS whole-file prefetch — deploy kit

This branch is a fork of rclone **v1.73.5** with one small patch plus a one-click
deploy kit for the rclone mount service used by Komga.

## The patch

Adds a new mount flag:

```
--vfs-cache-prefetch-max SizeSuffix
```

In `--vfs-cache-mode full`, when a file **no larger than** this size is opened,
rclone downloads the **whole file** into the cache in the background (a single
sequential download) instead of serving lots of small range requests.

Why: reading a `.zip`/`.cbz` comic archive over the mount makes the reader seek
randomly (central directory at the end, then back to each page). The stock
full-mode downloader keeps restarting/repositioning on every backward seek →
chunk thrashing → high iowait → "stalls after 2-3 pages". Prefetching the whole
small archive once removes the per-page requests.

Default is `0` (disabled) — stock behaviour. Set e.g. `--vfs-cache-prefetch-max 200M`.

Changed files: `vfs/vfscommon/options.go`, `vfs/vfscache/item.go`.

## Deploy on a new VPS

```bash
git clone -b komga-vfs-prefetch git@github.com:lhr404/rclone.git /opt/rclone-src
sudo /opt/rclone-src/deploy/deploy.sh
```

The script: installs Go if missing → builds the patched rclone → backs up the old
binary to `/usr/bin/rclone.orig` (first run only) → installs the new binary →
installs `/etc/init.d/rcloned` + `rcloned.service` → restarts the service.

**Secrets:** `rclone.conf` (with your OneDrive/GoogleDrive tokens) is **not** in
this repo. Put it at `/root/.config/rclone/rclone.conf` before the mounts work.

## Rollback

```bash
install -m755 /usr/bin/rclone.orig /usr/bin/rclone && systemctl restart rcloned
```

## Updating to a newer rclone version

The flag default is 0, so the change is self-contained and low-risk to carry
forward. To rebase onto a newer tag:

```bash
git rebase v1.74.0   # resolve any conflicts in the two changed files
```

## Files

- `deploy/deploy.sh` — one-click build + install + service setup
- `deploy/rcloned` — init script defining the gd / od / od1 mounts (already has
  `--vfs-cache-prefetch-max 200M`)
- `deploy/rcloned.service` — systemd unit that drives the init script
