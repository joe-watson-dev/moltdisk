#!/bin/zsh
# Builds a release binary and wraps it in MoltDisk.app (ad-hoc signed).
set -euo pipefail
cd "$(dirname "$0")/.."

# Version shown in Finder / About; CI passes the release tag number.
VERSION="${VERSION:-1.0}"
BUILD="${BUILD:-1}"

swift build -c release
APP="build/MoltDisk.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/MoltDisk "$APP/Contents/MacOS/MoltDisk"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>MoltDisk</string>
    <key>CFBundleDisplayName</key><string>MoltDisk</string>
    <key>CFBundleIdentifier</key><string>dev.moltdisk.MoltDisk</string>
    <key>CFBundleExecutable</key><string>MoltDisk</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "Built $PWD/$APP"
