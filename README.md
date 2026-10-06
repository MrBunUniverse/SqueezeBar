# SqueezeBar

Media optimizer for macOS 26+, living in your menu bar.

Drop images, video, audio or PDFs to compress them instantly, or stage them and tune each file first. Processing is 100% on-device with zero telemetry.

## Features

- **Quick drop and staged queue**: compress immediately, or queue files and set options per file.
- **Target sizes**: 2, 10, 25, 50 MB, custom, or manual quality control.
- **Formats**: images (HEIC, WebP, AVIF, JPEG), video (codec, frame rate, GIF export), audio (AAC), PDF (DPI, grayscale, metadata stripping).
- **Floating DropBall**: edge-docked desktop drop target.
- **Other inputs**: Finder Service, clipboard, watched folders.
- **Before/after inspector** and saved-space history.

## Build

```sh
cd macOS
./scripts/bundle_app.sh     # builds macOS/SqueezeBar.app
./scripts/create_dmg.sh     # optional DMG installer
```

## License

GPLv3. See [LICENSE](LICENSE).
