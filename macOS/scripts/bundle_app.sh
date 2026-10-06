#!/bin/bash
set -e
cd "$(dirname "$0")/.."

echo "[SqueezeBar] Building Release binary..."
swift build -c release

APP_NAME="SqueezeBar.app"
BUILD_BIN=".build/release/SqueezeBar"
DEST_APP="./${APP_NAME}"

echo "[SqueezeBar] Creating macOS App Bundle..."
rm -rf "${DEST_APP}"
mkdir -p "${DEST_APP}/Contents/MacOS"
mkdir -p "${DEST_APP}/Contents/Resources"

cp "${BUILD_BIN}" "${DEST_APP}/Contents/MacOS/SqueezeBar"
cp "Resources/Info.plist" "${DEST_APP}/Contents/Info.plist"
if [ -f "Resources/AppIcon.icns" ]; then
    cp "Resources/AppIcon.icns" "${DEST_APP}/Contents/Resources/AppIcon.icns"
fi

# Compile the string catalog into per-language .lproj folders (add translations to Resources/Localizable.xcstrings)
if [ -f "Resources/Localizable.xcstrings" ]; then
    echo "[SqueezeBar] Compiling localizations..."
    xcrun xcstringstool compile "Resources/Localizable.xcstrings" --output-directory "${DEST_APP}/Contents/Resources"
fi

# Optional codesign with ad-hoc signature for local execution
if command -v codesign &> /dev/null; then
    echo "[SqueezeBar] Signing application bundle with entitlements..."
    codesign --force --deep --sign - --entitlements "Resources/SqueezeBar.entitlements" "${DEST_APP}"
fi

echo "[SqueezeBar] Successfully built ${APP_NAME}"
echo "[SqueezeBar] Location: ${DEST_APP}"
