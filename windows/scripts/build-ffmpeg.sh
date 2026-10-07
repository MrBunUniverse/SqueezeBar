#!/bin/sh
# Build the size-trimmed FFmpeg the Windows app bundles as its fallback engine: only the codecs, formats and
# filters SqueezeBar.Media uses (see Compressors.cs, Ffmpeg.cs, MediaTests.cs). Drop-in for the stock build
# that fetch-ffmpeg.sh downloads: windows/vendor/ffmpeg/<arch>/ffmpeg.exe + LICENSE.txt.
# Cross-compiled on macOS with llvm-mingw; everything is static, GPL v2 or later (x264, x265).
#   brew install nasm pkgconf meson ninja cmake
#   ./scripts/build-ffmpeg.sh            # x64 and arm64
#   ./scripts/build-ffmpeg.sh arm64      # one of them
# Toolchain, sources and build trees live in windows/vendor/ffmpeg-build (gitignored, ~3 GB, safe to delete).
set -e
cd "$(dirname "$0")/.."
ROOT="$PWD"; B="$ROOT/vendor/ffmpeg-build"; S="$B/src"

LLVM_MINGW=20260922
FFMPEG=8.1.3
X264=b35605ace3ddf7c1a5d67a2eb553f034aef41d55   # stable branch
X265=4.2
SVTAV1=4.2.0
DAV1D=1.5.4
WEBP=1.6.0
OPUS=1.6.1
ZLIB=1.3.2

get() { # <dir> <tarball url>
  [ -d "$1" ] && return
  rm -rf "$1.part"; mkdir -p "$1.part"
  echo "fetching $2"
  curl -fsSL --retry 3 "$2" | tar -x -C "$1.part" --strip-components 1
  mv "$1.part" "$1"
}
get "$B/llvm-mingw" "https://github.com/mstorsjo/llvm-mingw/releases/download/$LLVM_MINGW/llvm-mingw-$LLVM_MINGW-ucrt-macos-universal.tar.xz"
get "$S/ffmpeg" "https://ffmpeg.org/releases/ffmpeg-$FFMPEG.tar.xz"
get "$S/x264"   "https://code.videolan.org/videolan/x264/-/archive/$X264/x264-$X264.tar.gz"
get "$S/x265"   "https://bitbucket.org/multicoreware/x265_git/get/$X265.tar.gz"
get "$S/svtav1" "https://gitlab.com/AOMediaCodec/SVT-AV1/-/archive/v$SVTAV1/SVT-AV1-v$SVTAV1.tar.gz"
get "$S/dav1d"  "https://code.videolan.org/videolan/dav1d/-/archive/$DAV1D/dav1d-$DAV1D.tar.gz"
get "$S/webp"   "https://storage.googleapis.com/downloads.webmproject.org/releases/webp/libwebp-$WEBP.tar.gz"
get "$S/opus"   "https://downloads.xiph.org/releases/opus/opus-$OPUS.tar.gz"
get "$S/zlib"   "https://github.com/madler/zlib/releases/download/v$ZLIB/zlib-$ZLIB.tar.gz"

export PATH="$B/llvm-mingw/bin:$PATH"
JOBS="$(sysctl -n hw.ncpu)"
SECTIONS="-ffunction-sections -fdata-sections"   # lets the linker drop unused functions

DECODERS="h264 hevc libdav1d vp8 vp9 mpeg4 mpeg2video prores mjpeg png webp bmp tiff gif
  aac mp3 opus vorbis flac alac ac3 eac3 mp2 pcm_* rawvideo wrapped_avframe"   # wrapped_avframe: what lavfi sources hand over
ENCODERS="libx264 libx265 h264_mf hevc_mf aac gif libwebp libsvtav1 png libopus"
DEMUXERS="mov matroska avi mpegts flv wav mp3 ogg flac aiff caf aac gif image2
  image_png_pipe image_jpeg_pipe image_webp_pipe image_bmp_pipe image_tiff_pipe"
MUXERS="mp4 ipod gif webp avif image2 matroska ogg"
PARSERS="h264 hevc av1 vp8 vp9 mpeg4video mpegvideo mjpeg png webp bmp gif aac ac3 mpegaudio opus vorbis flac"
FILTERS="scale fps split palettegen paletteuse format aresample testsrc2 sine"
BSFS="aac_adtstoasc extract_extradata h264_mp4toannexb hevc_mp4toannexb"
list() { flag="$1"; shift; for item in "$@"; do printf -- '--enable-%s=%s ' "$flag" "$item"; done; }

build() { # <x64|arm64>
  ARCH="$1"
  case "$ARCH" in x64) CPU=x86_64 ;; arm64) CPU=aarch64 ;; *) echo "unknown arch $ARCH"; exit 1 ;; esac
  T="$CPU-w64-mingw32"; P="$B/$ARCH/prefix"; BD="$B/$ARCH/build"
  mkdir -p "$P/lib/pkgconfig" "$P/include" "$BD"
  export PKG_CONFIG_LIBDIR="$P/lib/pkgconfig"

  cm() { # <name> <source dir> [cmake options]: configure, build and install a CMake library, once
    name="$1"; src="$2"; shift 2
    [ -f "$BD/$name.done" ] && return
    cmake -S "$src" -B "$BD/$name" -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
      -DCMAKE_SYSTEM_NAME=Windows -DCMAKE_SYSTEM_PROCESSOR="$CPU" -DCMAKE_C_COMPILER="$T-clang" -DCMAKE_CXX_COMPILER="$T-clang++" \
      -DCMAKE_RC_COMPILER="$T-windres" -DCMAKE_ASM_NASM_COMPILER=nasm -DCMAKE_C_FLAGS="$SECTIONS" -DCMAKE_CXX_FLAGS="$SECTIONS" \
      -DCMAKE_INSTALL_PREFIX="$P" -DCMAKE_INSTALL_LIBDIR=lib -DCMAKE_FIND_ROOT_PATH="$P" -DBUILD_SHARED_LIBS=OFF "$@"
    cmake --build "$BD/$name"
    cmake --install "$BD/$name"
    touch "$BD/$name.done"
  }

  if [ ! -f "$BD/zlib.done" ]; then # its Makefile.gcc builds in the source tree, so work on a copy
    rm -rf "$BD/zlib"; cp -R "$S/zlib" "$BD/zlib"
    make -C "$BD/zlib" -f win32/Makefile.gcc -j"$JOBS" PREFIX="$T-" libz.a
    cp "$BD/zlib/libz.a" "$P/lib/"; cp "$BD/zlib/zlib.h" "$BD/zlib/zconf.h" "$P/include/"
    touch "$BD/zlib.done"
  fi

  if [ ! -f "$BD/x264.done" ]; then
    mkdir -p "$BD/x264"
    (cd "$BD/x264" && "$S/x264/configure" --host="$T" --cross-prefix="$T-" --prefix="$P" --enable-static --disable-cli \
      --disable-opencl --bit-depth=8 --extra-cflags="$SECTIONS" && make -j"$JOBS" && make install)
    touch "$BD/x264.done"
  fi

  # 8-bit only: the app always encodes yuv420p. CROSS_COMPILE_ARM64 stops x265 probing the Mac's CPU features.
  [ "$ARCH" = arm64 ] && X265_ARM="-DCROSS_COMPILE_ARM64=ON" || X265_ARM=""
  cm x265 "$S/x265/source" -DENABLE_SHARED=OFF -DENABLE_CLI=OFF -DHIGH_BIT_DEPTH=OFF $X265_ARM
  cm svtav1 "$S/svtav1" -DBUILD_APPS=OFF -DBUILD_TESTING=OFF -DSVT_AV1_LTO=OFF
  cm webp "$S/webp" -DWEBP_BUILD_ANIM_UTILS=OFF -DWEBP_BUILD_CWEBP=OFF -DWEBP_BUILD_DWEBP=OFF -DWEBP_BUILD_GIF2WEBP=OFF \
    -DWEBP_BUILD_IMG2WEBP=OFF -DWEBP_BUILD_VWEBP=OFF -DWEBP_BUILD_WEBPINFO=OFF -DWEBP_BUILD_WEBPMUX=OFF -DWEBP_BUILD_EXTRAS=OFF \
    -DWEBP_BUILD_LIBWEBPMUX=OFF
  # Opus only makes test fixtures; its ARM CPU detection does not know mingw, so plain C it is.
  cm opus "$S/opus" -DOPUS_BUILD_PROGRAMS=OFF -DOPUS_BUILD_TESTING=OFF -DOPUS_DISABLE_INTRINSICS=ON

  if [ ! -f "$BD/dav1d.done" ]; then
    cat > "$BD/meson-cross.ini" <<EOF
[binaries]
c = '$T-clang'
ar = '$T-ar'
strip = '$T-strip'
windres = '$T-windres'
[host_machine]
system = 'windows'
cpu_family = '$CPU'
cpu = '$CPU'
endian = 'little'
EOF
    meson setup "$BD/dav1d" "$S/dav1d" --cross-file "$BD/meson-cross.ini" --prefix "$P" --libdir lib --buildtype release \
      --default-library static -Denable_tools=false -Denable_tests=false
    ninja -C "$BD/dav1d" install
    touch "$BD/dav1d.done"
  fi

  mkdir -p "$BD/ffmpeg"
  # shellcheck disable=SC2046 # the lists are meant to split into one flag per item
  (cd "$BD/ffmpeg" && "$S/ffmpeg/configure" --arch="$CPU" --target-os=mingw32 --cross-prefix="$T-" \
    --pkg-config=pkg-config --pkg-config-flags=--static \
    --extra-cflags="-I$P/include $SECTIONS" --extra-ldflags="-L$P/lib -static -Wl,--gc-sections" \
    --enable-gpl --disable-everything --disable-autodetect --disable-doc --disable-debug --disable-network \
    --disable-ffprobe --disable-ffplay --disable-pthreads --enable-w32threads \
    --enable-zlib --enable-mediafoundation --enable-d3d11va --enable-libx264 --enable-libx265 --enable-libsvtav1 --enable-libdav1d \
    --enable-libwebp --enable-libopus --enable-indev=lavfi --enable-protocol=file --enable-protocol=pipe \
    $(list decoder $DECODERS) $(list encoder $ENCODERS) $(list demuxer $DEMUXERS) $(list muxer $MUXERS) \
    $(list parser $PARSERS) $(list filter $FILTERS) $(list bsf $BSFS) \
    && make -j"$JOBS")

  OUT="$ROOT/vendor/ffmpeg/$ARCH"; mkdir -p "$OUT"
  cp "$BD/ffmpeg/ffmpeg.exe" "$OUT/ffmpeg.exe"
  {
    echo "ffmpeg.exe is a custom static build of FFmpeg $FFMPEG, licensed as a whole under the GNU General Public"
    echo "License version 2 or later. It was built by windows/scripts/build-ffmpeg.sh in the SqueezeBar source, which"
    echo "names the exact source versions and build options. It contains these libraries, whose licences follow:"
    echo "x264 ($X264), x265 $X265, SVT-AV1 $SVTAV1, dav1d $DAV1D, libwebp $WEBP, Opus $OPUS, zlib $ZLIB."
    for f in ffmpeg/LICENSE.md ffmpeg/COPYING.GPLv2 x264/COPYING x265/COPYING svtav1/LICENSE.md svtav1/PATENTS.md \
             dav1d/COPYING webp/COPYING webp/PATENTS opus/COPYING zlib/LICENSE; do
      printf '\n\n======== %s ========\n\n' "$f"; cat "$S/$f"
    done
  } > "$OUT/LICENSE.txt"
  ls -la "$OUT"
}

for ARCH in ${@:-x64 arm64}; do build "$ARCH"; done
