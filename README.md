# SqueezeBar

Media optimizer for macOS 26+ and Windows 11, living in your menu bar or system tray.

Drop images, video, audio or PDFs to compress them instantly, or stage them and tune each file first. Processing is 100% on-device with zero telemetry.

## Downloads

<p>
  <a href="https://github.com/MrBunUniverse/SqueezeBar/releases/latest/download/SqueezeBar.dmg"><img src="docs/download-macos.svg" alt="Download for macOS" height="56"></a>
  <a href="https://github.com/MrBunUniverse/SqueezeBar/releases/latest/download/SqueezeBar-windows-x64.zip"><img src="docs/download-windows-x64.svg" alt="Download for Windows x64" height="56"></a>
  <a href="https://github.com/MrBunUniverse/SqueezeBar/releases/latest/download/SqueezeBar-windows-arm64.zip"><img src="docs/download-windows-arm64.svg" alt="Download for Windows ARM64" height="56"></a>
</p>

On Windows, unzip anywhere and run `SqueezeBar.exe`; no install, .NET or Windows App SDK needed. The app is unsigned, so SmartScreen may warn on first launch. Older builds are on [Releases](../../releases).

## Features

- **Quick drop and staged queue**: compress immediately, or queue files and set options per file.
- **Target sizes**: 2, 10, 25, 50 MB, custom, or manual quality control.
- **Formats**: images (HEIC, WebP, AVIF, JPEG), video (codec, frame rate, GIF export), audio (AAC), PDF (DPI, grayscale, metadata stripping).
- **Floating DropBall** (macOS): edge-docked desktop drop target.
- **Other inputs**: Finder Service or Explorer right-click menu, clipboard, watched folders.
- **Before/after inspector** and saved-space history (macOS).

### Windows 11

A native WinUI 3 app that lives in the system tray, with the same quick drop, per-file queue, target sizes and watched folders. It uses Windows' built-in codecs first and falls back to a bundled FFmpeg only for formats Windows can't handle (HEVC without the paid extension, MKV/WebM, GIF, WebP, AVIF). Nothing is downloaded at runtime.

## Build

```sh
cd macOS
./scripts/bundle_app.sh     # builds macOS/SqueezeBar.app
./scripts/create_dmg.sh     # optional DMG installer
```

Windows (.NET 9 SDK, on Windows): `windows/scripts/publish.sh [arm64|x64]` writes `windows/dist/SqueezeBar-<arch>/SqueezeBar.exe`.

## License

GPLv3. See [LICENSE](LICENSE).
