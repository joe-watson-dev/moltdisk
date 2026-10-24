#!/bin/zsh
# Renders scripts/og-image.html to landing/og-image.png (1200×630) with headless Chrome.
set -euo pipefail
cd "$(dirname "$0")/.."
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
"$CHROME" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=1 \
  --window-size=1200,630 --virtual-time-budget=4000 \
  --screenshot="$PWD/landing/og-image.png" "file://$PWD/scripts/og-image.html" >/dev/null 2>&1
echo "Wrote $PWD/landing/og-image.png"
