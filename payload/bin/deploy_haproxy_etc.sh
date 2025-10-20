#!/usr/bin/env bash
set -euo pipefail

ARCHIVE="${1:-/work/archives/haproxy-etc.tar.gz}"

DEST="/host/etc/haproxy"   # в докере смонтируешь /etc/haproxy -> /host/etc/haproxy

if [ -z "$ARCHIVE" ]; then
  echo "Usage: $0 <archive>" >&2
  exit 1
fi

if [ ! -f "$ARCHIVE" ]; then
  echo "Archive not found: $ARCHIVE" >&2
  exit 1
fi

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

echo "[*] Extracting $ARCHIVE -> $TMPDIR"
case "$ARCHIVE" in
  *.tar.gz|*.tgz) tar -xzf "$ARCHIVE" -C "$TMPDIR" ;;
  *.tar.bz2|*.tbz2) tar -xjf "$ARCHIVE" -C "$TMPDIR" ;;
  *.tar.xz|*.txz) tar -xJf "$ARCHIVE" -C "$TMPDIR" ;;
  *.tar) tar -xf "$ARCHIVE" -C "$TMPDIR" ;;
  *.zip) unzip -q "$ARCHIVE" -d "$TMPDIR" ;;
  *.rar) unrar x -o+ "$ARCHIVE" "$TMPDIR/" ;;
  *) echo "Unsupported archive format: $ARCHIVE" >&2; exit 1 ;;
esac

echo "[*] Copying files to $DEST"
mkdir -p "$DEST"
cp -rT "$TMPDIR" "$DEST"

echo "[*] Done"
