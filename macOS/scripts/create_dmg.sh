#!/bin/bash
set -e
cd "$(dirname "$0")/.."

# ==============================================================================
# SqueezeBar DMG Installer Builder
# Creates a professional drag-and-drop macOS DMG installer with baked-in arrow & background layout
# ==============================================================================

APP_NAME="SqueezeBar"
VERSION="1.1.0"
OUTPUT_DMG="${APP_NAME}-${VERSION}.dmg"

echo "=========================================="
echo " Building ${APP_NAME} DMG Installer"
echo "=========================================="

# 1. Build and package the production app bundle
./scripts/bundle_app.sh

if [ ! -d "${APP_NAME}.app" ]; then
    echo "Error: ${APP_NAME}.app not found!"
    exit 1
fi

# 2. Render the background, then build a styled DMG with hdiutil + Finder layout
swiftc -O scripts/make_dmg_background.swift -o "${TMPDIR:-/tmp}/mkbg"
"${TMPDIR:-/tmp}/mkbg" Resources/dmg_background.png

rm -f "${OUTPUT_DMG}" "SqueezeBar"*.dmg
STAGE="$(mktemp -d)"
RW_DMG="${STAGE}/rw.dmg"
VOL="${APP_NAME}"
hdiutil detach "/Volumes/${VOL}" -force >/dev/null 2>&1 || true

mkdir -p "${STAGE}/src/.background"
cp -R "${APP_NAME}.app" "${STAGE}/src/"
cp Resources/dmg_background.png "${STAGE}/src/.background/background.png"
ln -s /Applications "${STAGE}/src/Applications"

hdiutil create -srcfolder "${STAGE}/src" -volname "${VOL}" -fs HFS+ -format UDRW -ov "${RW_DMG}" >/dev/null
hdiutil attach "${RW_DMG}" -mountpoint "/Volumes/${VOL}" -noautoopen >/dev/null

osascript <<OSA
tell application "Finder"
  tell disk "${VOL}"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 920, 588}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 128
    set text size of opts to 14
    set background picture of opts to file ".background:background.png"
    set position of item "${APP_NAME}.app" of container window to {180, 205}
    set position of item "Applications" of container window to {540, 205}
    close
    open
    update without registering applications
    delay 2
    close
  end tell
end tell
OSA

sync
hdiutil detach "/Volumes/${VOL}" >/dev/null
hdiutil convert "${RW_DMG}" -format UDZO -imagekey zlib-level=9 -o "${OUTPUT_DMG}" >/dev/null
rm -rf "${STAGE}"

echo "=========================================="
echo " Successfully created DMG installer:"
echo " File: ./${OUTPUT_DMG}"
echo " Size: $(du -h "${OUTPUT_DMG}" | awk '{print $1}')"
echo "=========================================="
