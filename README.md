# SqueezeBar

Universal media optimizer for macOS and Windows.

SqueezeBar provides effortless 1-drop batch media compression, dual-zone quick/staged workflows, and per-file fine-tuning with zero telemetry and 100% on-device processing.

---

## Download & Run

- **macOS**: Download [`SqueezeBar-0.98.dmg`](https://github.com/MrBunUniverse/SquezeBar/releases/latest) -> Open & drag to Applications.
- **Windows (Beta)**: Download [`SqueezeBar.exe`](https://github.com/MrBunUniverse/SquezeBar/releases/latest) -> Double-click to run *(Portable, no installation required)*.

---

## Features

- **1-Drop Batch Optimization**: Instant Quick Drop or queue and customize files individually.
- **Smart Target Sizes**: Compression presets for Discord (25MB/50MB), Email (10MB), or Custom limits.
- **Full Quality & Format Controls**: Adjust quality, resolution scaling, framerate, and convert formats.
- **Desktop Floating Drop Ball (macOS)**: Edge-docking drop zone for quick drag-and-drop.
- **100% Local & Private**: On-device hardware-accelerated processing with zero telemetry.

---

## Build from Source

### macOS
```bash
cd macOS
./scripts/bundle_app.sh
# Or create the DMG installer
./scripts/create_dmg.sh
```

### Windows
```bash
./windows/scripts/build_windows.sh
```

---

## License

This project is licensed under the **GNU General Public License v3.0 (GPLv3)**. See the [LICENSE](LICENSE) file for details.
