#!/bin/sh
# Download stock FFmpeg binaries as the fallback engine (not kept in git). Releases bundle the trimmed build from
# build-ffmpeg.sh instead; this is the quick alternative. Only ffmpeg.exe is kept: windows/vendor/ffmpeg/<arch>/ffmpeg.exe
# Source: BtbN/FFmpeg-Builds, the Windows build provider listed on ffmpeg.org. GPL build (x264, x265),
# compatible with SqueezeBar's GPLv3. Pinned to one dated build (month-end builds are kept long-term), checked
# against the SHA-256 digests GitHub publishes for those release assets. To update: pick a newer
# autobuild-YYYY-MM-DD tag and copy the new names and digests from
# https://api.github.com/repos/BtbN/FFmpeg-Builds/releases/tags/<tag>.
set -e
cd "$(dirname "$0")/.."
TAG="autobuild-2026-09-30-13-08"
BUILD="ffmpeg-n8.1.3-9-g29e619e767"
for ENTRY in \
  "x64:win64:7b801cdd3a1a0bb54ae6f572187e68b4ed54f52086cfee133fab2180bfb429fa" \
  "arm64:winarm64:061a770557c30bbf8e0b6ca3810288a60f72b85088378b84be03277746f34f17"; do
  ARCH="${ENTRY%%:*}"; REST="${ENTRY#*:}"; PLATFORM="${REST%%:*}"; SHA="${REST#*:}"
  NAME="$BUILD-$PLATFORM-gpl-8.1"
  mkdir -p "vendor/ffmpeg/$ARCH"
  [ -f "vendor/ffmpeg/$ARCH/ffmpeg.exe" ] && { echo "$ARCH: already present"; continue; }
  TMP="$(mktemp -d)"
  curl -fL --progress-bar -o "$TMP/ffmpeg.zip" "https://github.com/BtbN/FFmpeg-Builds/releases/download/$TAG/$NAME.zip"
  echo "$SHA  $TMP/ffmpeg.zip" | shasum -a 256 -c - || { rm -rf "$TMP"; echo "checksum mismatch for $NAME.zip"; exit 1; }
  unzip -q -j "$TMP/ffmpeg.zip" "$NAME/bin/ffmpeg.exe" "$NAME/LICENSE.txt" -d "vendor/ffmpeg/$ARCH"
  rm -rf "$TMP"
  ls -la "vendor/ffmpeg/$ARCH"
done
