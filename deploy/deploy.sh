#!/usr/bin/env bash
#
# One-click deploy for the patched rclone (adds --vfs-cache-prefetch-max) plus
# the rcloned mount service. Build-from-source: no prebuilt binary is shipped,
# so this works on any architecture.
#
# Usage (on a fresh VPS):
#   git clone -b komga-vfs-prefetch git@github.com:lhr404/rclone.git /opt/rclone-src
#   sudo /opt/rclone-src/deploy/deploy.sh
#
# Re-running is safe (idempotent). The original /usr/bin/rclone, if present, is
# backed up to /usr/bin/rclone.orig the first time only.
#
# NOTE: rclone.conf (with your OneDrive/GoogleDrive tokens) is NOT in this repo.
#       Put it at /root/.config/rclone/rclone.conf before the mounts will work.

set -euo pipefail

# Resolve the rclone source tree = parent of this deploy/ dir
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RCLONE_BIN=/usr/bin/rclone

echo ">>> rclone source: $SRC_DIR"
cd "$SRC_DIR"

# ---- 1. Make sure a Go toolchain is available ---------------------------------
# go.mod pins `go 1.25.0`; with GOTOOLCHAIN=auto any Go >= 1.21 will fetch the
# exact toolchain automatically. If Go is missing entirely, download the latest
# stable release for this architecture.
export GOTOOLCHAIN=auto
need_go=1
if command -v go >/dev/null 2>&1; then
  # Treat any installed go as good enough; GOTOOLCHAIN=auto upgrades as needed.
  need_go=0
fi
if [[ "$need_go" -eq 1 ]]; then
  echo ">>> Go not found, downloading latest stable Go..."
  arch="$(uname -m)"
  case "$arch" in
    x86_64|amd64) goarch=amd64 ;;
    aarch64|arm64) goarch=arm64 ;;
    armv7l|armv6l) goarch=armv6l ;;
    *) echo "Unsupported arch: $arch" >&2; exit 1 ;;
  esac
  gover="$(curl -fsSL 'https://go.dev/VERSION?m=text' | head -1)"
  echo ">>> Installing ${gover}.linux-${goarch} to /usr/local/go"
  curl -fsSL "https://go.dev/dl/${gover}.linux-${goarch}.tar.gz" -o /tmp/go.tgz
  rm -rf /usr/local/go
  tar -C /usr/local -xzf /tmp/go.tgz
  rm -f /tmp/go.tgz
  export PATH=/usr/local/go/bin:$PATH
fi
echo ">>> Using $(go version)"

# ---- 2. Build the patched rclone ----------------------------------------------
echo ">>> Building rclone (this fetches modules on first run, ~1-2 min)..."
go build -trimpath -ldflags "-s -w" -o /tmp/rclone-built .

# ---- 3. Install the binary (backup original once) -----------------------------
if [[ -f "$RCLONE_BIN" && ! -f "${RCLONE_BIN}.orig" ]]; then
  cp -a "$RCLONE_BIN" "${RCLONE_BIN}.orig"
  echo ">>> Backed up existing rclone -> ${RCLONE_BIN}.orig"
fi
install -m 0755 /tmp/rclone-built "$RCLONE_BIN"
rm -f /tmp/rclone-built
echo ">>> Installed: $($RCLONE_BIN version | head -1)"
"$RCLONE_BIN" mount --help 2>/dev/null | grep -q 'vfs-cache-prefetch-max' \
  && echo ">>> OK: --vfs-cache-prefetch-max present" \
  || { echo "ERROR: patched flag missing!" >&2; exit 1; }

# ---- 4. Install the mount service ---------------------------------------------
install -m 0755 "$SCRIPT_DIR/rcloned" /etc/init.d/rcloned
install -m 0644 "$SCRIPT_DIR/rcloned.service" /etc/systemd/system/rcloned.service
echo ">>> Installed /etc/init.d/rcloned and rcloned.service"

if [[ ! -f /root/.config/rclone/rclone.conf ]]; then
  echo ">>> WARNING: /root/.config/rclone/rclone.conf not found."
  echo "    Copy your rclone.conf (with remote tokens) there, then run:"
  echo "      systemctl daemon-reload && systemctl enable --now rcloned"
  exit 0
fi

systemctl daemon-reload
systemctl enable rcloned >/dev/null 2>&1 || true
systemctl restart rcloned
sleep 4
echo ">>> Service status: $(systemctl is-active rcloned)"
mount | grep -iE 'OneDrive|GoogleDrive' || echo "(no mounts yet - check 'journalctl -u rcloned' and the log files)"
echo ">>> Done."
