#!/bin/sh
# Installs MoltDisk: downloads the latest release from GitHub and puts MoltDisk.app in Applications.
#   curl -fsSL https://moltdisk.vercel.app/install.sh | sh
#
# MoltDisk isn't signed by Apple yet. A browser download is tagged as "from the internet" and macOS then
# blocks it as coming from an unidentified developer; a download made with curl isn't tagged, so the app
# opens normally. The source is public: https://github.com/joe-watson-sbf/moltdisk
set -eu

URL="https://github.com/joe-watson-sbf/moltdisk/releases/latest/download/MoltDisk.zip"

fail() { printf '\033[31m%s\033[0m\n' "$1" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || fail "MoltDisk is a Mac app."
[ "$(uname -m)" = "arm64" ] || fail "MoltDisk needs a Mac with Apple silicon (M1 or newer)."
major=$(sw_vers -productVersion | cut -d. -f1)
[ "$major" -ge 15 ] || fail "MoltDisk needs macOS 15 Sequoia or later (this Mac has $(sw_vers -productVersion))."

# /Applications when it's writable, otherwise ~/Applications (no password needed).
if [ -w /Applications ]; then dest=/Applications; else dest="$HOME/Applications"; mkdir -p "$dest"; fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

echo "Downloading MoltDisk…"
curl -fsSL "$URL" -o "$tmp/MoltDisk.zip" || fail "Download failed: $URL"
ditto -x -k "$tmp/MoltDisk.zip" "$tmp"
[ -d "$tmp/MoltDisk.app" ] || fail "The download didn't contain MoltDisk.app."

if [ -d "$dest/MoltDisk.app" ]; then
  pkill -x MoltDisk 2>/dev/null || true
  rm -rf "$dest/MoltDisk.app"
fi
mv "$tmp/MoltDisk.app" "$dest/MoltDisk.app"
# In case the zip carried the tag from a browser download along the way.
xattr -dr com.apple.quarantine "$dest/MoltDisk.app" 2>/dev/null || true

echo "Installed $dest/MoltDisk.app"
open "$dest/MoltDisk.app"
