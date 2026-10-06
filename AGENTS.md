# SqueezeBar

macOS 26+ menu-bar media compressor (images, video, audio, PDF). SwiftPM, no third-party deps, 100% on-device, zero telemetry. Mac source is under `macOS/`. A Windows 11 port (WinUI 3, C#) is being rebuilt in `windows/`; so far only `SqueezeBar.Core` (engine logic, no UI) exists, tested with `dotnet test windows/SqueezeBar.Core.Tests`. Ignore the old Avalonia `windows/` in git history.

## Commands (run from `macOS/`)

```sh
swift build                # compile
swift test                 # XCTest: classification, image output, orientation, file drag
./scripts/bundle_app.sh    # release build -> macOS/SqueezeBar.app (deletes and recreates it)
./scripts/create_dmg.sh    # DMG via npx create-dmg; deletes top-level macOS/SqueezeBar*.dmg first
./scripts/update_strings.sh # re-extract UI strings into Resources/Localizable.xcstrings
```

Generated, never edit: `macOS/.build/`, `macOS/SqueezeBar.app`, `macOS/dist/`, `*.dmg`.

## Workflow rules

- **After any UI, runtime or feature change:** run `./scripts/bundle_app.sh`, quit the running project copy, relaunch `macOS/SqueezeBar.app` (not one in `/Applications`). Keep user preferences. If blocked, say why; don't imply it's updated. Doc-only edits skip this.
- Start with `git status --short`; the tree is often dirty. Preserve existing edits.
- Behavior change: run the narrow relevant tests. A successful bundle is not proof of runtime behavior; the UI, folder watch and end-to-end jobs have no tests.
- No network services or new dependencies without a clear product need.
- Version `1.1.0` lives in three places; keep them in sync: `Resources/Info.plist`, Activity footer in `UI/QuickPopoverView.swift`, `scripts/create_dmg.sh`.
- GPU profiling: stop live window sharing first, or readings measure WindowServer, not the app.

## Architecture (`macOS/Sources/SqueezeBar/`)

Entry: `App/AppDelegate.swift` (accessory app, Finder Service, folder watch, DropBall, first-run `UI/WelcomeView.swift`).

Flow: every input (menu bar, quick drop, DropBall, Finder, clipboard, watch folder) -> `MediaCompressionEngine.processDroppedURLs`. The staged queue -> `processStagedItems`. Both expand folders, classify, snapshot settings, dispatch to a compressor, and report to `AppState`. Concurrency cap: 2 jobs on <=8 processors, else 4.

| Area | File | Notes |
| --- | --- | --- |
| Engine actor | `Engine/MediaCompressionEngine.swift` | Jobs, destinations, collision-safe naming, Downloads fallback, cancellation. Put shared behavior here so all entry paths stay consistent. |
| Compressors | `Engine/AcceleratedImageCompressor`, `HardwareVideoCompressor`, `HardwareAudioCompressor`, `AcceleratedPDFCompressor` | Output extension choice and actual encoding must agree. |
| Watch folder | `Engine/FolderWatchService.swift` | |
| State | `Models/AppState.swift` | `@MainActor` singleton; `UserDefaults` prefs; history JSON, capped at 50. |
| Config | `Models/CompressionModels.swift` | Enums, `CompressionConfiguration`; type classification via `UTType` + extension fallback. `AppState.currentConfiguration()` makes the per-run snapshot. |
| Staged items | `Models/StagedQueueItem.swift` | Per-file overrides on the base config. Quick drops use one snapshot for the whole batch; keep that distinction. |
| Menu bar | `UI/StatusBarController.swift`, `StatusItemDropView.swift` | |
| Main UI | `UI/QuickPopoverView.swift` (~4.7k lines) | Activity, Settings, drawers, history. Make local edits in existing patterns; don't refactor for small features. Also shown by `FloatingDropWindow.swift`. |
| Queue settings | `UI/QueueItemSettingsSheet.swift` | |
| DropBall | `UI/FloatingBallController.swift` (panel, docking, physics), `FloatingBallView.swift` (render, drops) | Click-through outside the visible oval. |
| Inspector | `UI/BeforeAfterInspectorView.swift` | Before/after compare. |

Persistent setting checklist: keep the `UserDefaults` key, published property, default loading, `currentConfiguration()` snapshot and UI binding in sync. Don't rename keys without a migration.

Target sizes: 2, 10, 25, 50 MB, custom, manual. Output defaults beside the input with a configurable suffix; custom folder/subfolder can override.

## Pause, cancel and localization

- **Pause/cancel:** each job has a `JobControl` (`Engine/JobControl.swift`) looked up through `JobControlRegistry`; the UI (`AppState.pauseJob`, `resumeJob`, `cancelJob`) talks to it directly, never through the engine actor. Video and audio encodes block in `checkpoint()` on their own queues while paused (GIF polls); images and PDFs only honor cancel. Never call `checkpoint()` from the main thread or the engine actor.
- **Cancel sentinel:** the string `"Cancelled"` is compared in logic (`job.error == "Cancelled"`); it is an internal marker, not display text. Displayed status text is localized separately.
- **Localization:** all UI text must be localizable. `Text("literal")`, `Label`, `.help` etc. are automatic. For plain `String` UI text use `String(localized:)`. Enum raw values are persisted in UserDefaults and must never change; show `displayName` / `shortName` from `Models/DisplayNames.swift` instead. After changing UI text run `./scripts/update_strings.sh`. To add a language, add translations in `Resources/Localizable.xcstrings`; `bundle_app.sh` compiles them into the app.
- **No paid tier:** every feature is free. Do not add feature gating or purchase flows.

## Gotchas

- **Orientation:** images bake EXIF rotation/mirroring into pixels before resize/strip. Video encodes the unrotated track dimensions and carries rotation in the output track transform; don't swap dimensions and rotate again. GIF applies the track transform to pixels via a video composition.
- **Sandbox/permissions:** `Resources/SqueezeBar.entitlements` grants selected-file R/W, app-scoped bookmarks, movies/pictures, Downloads. Changing file access means checking entitlements and security-scoped URL handling together.
- **Cross-path changes:** trace one real call path end to end first. A UI-only guard leaves sibling input paths inconsistent.
- `Resources/Onboarding/*.jpg` is retired tour artwork, not bundled; leave it or delete it.
