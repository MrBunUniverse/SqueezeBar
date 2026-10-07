#!/bin/sh
# Download the FFmpeg binaries the Windows app bundles as its fallback engine (not kept in git).
# Source: BtbN/FFmpeg-Builds, the Windows build provider listed on ffmpeg.org. GPL build (x264, x265),
# compatible with SqueezeBar's GPLv3. Only ffmpeg.exe is kept: windows/vendor/ffmpeg/<arch>/ffmpeg.exe
set -e
cd "$(dirname "$0")/.."
VERSION="n8.1"
for PAIR in "x64:win64" "arm64:winarm64"; do
  ARCH="${PAIR%%:*}"; NAME="ffmpeg-$VERSION-latest-${PAIR##*:}-gpl-${VERSION#n}"
  mkdir -p "vendor/ffmpeg/$ARCH"
  [ -f "vendor/ffmpeg/$ARCH/ffmpeg.exe" ] && { echo "$ARCH: already present"; continue; }
  TMP="$(mktemp -d)"
  curl -fL --progress-bar -o "$TMP/ffmpeg.zip" "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/$NAME.zip"
  unzip -q -j "$TMP/ffmpeg.zip" "$NAME/bin/ffmpeg.exe" "$NAME/LICENSE.txt" -d "vendor/ffmpeg/$ARCH"
  rm -rf "$TMP"
  ls -la "vendor/ffmpeg/$ARCH"
done
