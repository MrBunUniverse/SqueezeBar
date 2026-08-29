#!/bin/bash
set -e
cd "$(dirname "$0")/.."

# ==============================================================================
# SqueezeBar DMG Installer Builder
# Creates a professional drag-and-drop macOS DMG installer with baked-in arrow & background layout
# ==============================================================================

APP_NAME="SqueezeBar"
VERSION="1.0.0"
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

# 2. Build DMG using create-dmg for reliable .DS_Store background and arrow layout
rm -f "${OUTPUT_DMG}" "SqueezeBar"*.dmg
npx --yes create-dmg "${APP_NAME}.app" . --overwrite --no-code-sign --no-version-in-filename

# Rename to standardized release name
if [ -f "${APP_NAME}.dmg" ]; then
    mv "${APP_NAME}.dmg" "${OUTPUT_DMG}"
elif [ -f "${APP_NAME} ${VERSION}.dmg" ]; then
    mv "${APP_NAME} ${VERSION}.dmg" "${OUTPUT_DMG}"
fi

echo "=========================================="
echo " Successfully created DMG installer:"
echo " File: ./${OUTPUT_DMG}"
echo " Size: $(du -h "${OUTPUT_DMG}" | awk '{print $1}')"
echo "=========================================="
