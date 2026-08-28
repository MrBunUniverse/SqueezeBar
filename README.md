# SqueezeBar

A lightweight, universal media compression utility for **macOS** and **Windows**.

SqueezeBar provides effortless 1-drop batch media compression, dual-zone quick/staged workflows, and per-file fine-tuning with zero telemetry and 100% on-device processing.

---

## Download & Run

- macOS**: Download **[`SqueezeBar-0.98.dmg`](https://github.com/MrBunUniverse/SquezeBar/releases/latest)** → Open & drag to Applications.
- Windows (Beta)**: Download **[`SqueezeBar.exe`](https://github.com/MrBunUniverse/SquezeBar/releases/latest)** → Double-click to run
---

## Features
- **Dual-Zone Interface**: Instant Quick Drop + Custom Staged Queue with per-file sliders.
- **1:1 Multi-Deck Controls**: Continuous quality sliders, target size automation (25MB Discord, 10MB Email, Custom MB), resolution scaling, framerate selection (FPS), and format conversion.
- **Individual Per-File Customization**: Custom settings per queued media item before squeezing.
- **macOS Floating Drop Ball**: Edge-docking magnetic liquid glass basket with Apple bezel edge-tab morphing and proximity cursor detection.
- **Zero Telemetry & 100% Local**: All processing executes purely on-device with privacy-first metadata stripping.

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
