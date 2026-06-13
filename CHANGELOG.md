# Changelog

## 1.1.0

- Added three new warm editorial widget variants using paper tones, serif typography, thin dividers, and muted progress bars.
- Kept the widget data source unchanged: the new widgets read the same cached Codex limit snapshot as the existing widget.
- Made the editorial progress bar explicitly show the weekly limit, removed request counts, and show the exact 5-hour reset time.

## 1.0.9

- Simplified Widget settings to keep only the `Show last updated time` toggle.
- Normalized removed widget display settings back to enabled so existing installs cannot get stuck with hidden limits.

## 1.0.8

- Fixed empty widgets in ad-hoc builds by writing the cached snapshot and settings to the WidgetKit extension support container as a local fallback.

## 1.0.7

- Added an App Group `UserDefaults` fallback for cached snapshots and widget settings so WidgetKit can still read data when file-based App Group reads return empty.

## 1.0.6

- Fixed widget refresh visibility by showing the last successful snapshot update time directly on the widget.
- Made WidgetKit extension read and apply saved widget display preferences.
- Reloaded widget timelines after both successful refreshes and cached error updates.

## 1.0.5

- Replaced the installer script in release archives with a standard drag-to-Applications DMG layout.
- Added a custom DMG background with an arrow from the app icon to the Applications shortcut.

## 1.0.4

- Removed direct reads and writes to the WidgetKit extension container to stop macOS from repeatedly asking for access to data from other apps.
- Kept shared widget data on the App Group container and normal application support fallback only.

## 1.0.3

- Fixed the app icon shown in macOS widget picker by bundling `AppIcon.icns` in both the host app and WidgetKit extension and declaring `CFBundleIconFile` for each bundle.

## 1.0.2

- Fixed long-running refresh hangs when `codex app-server --stdio` stops returning a JSON-RPC response.
- Reworked Codex stdout reading to use asynchronous pipe readiness instead of blocking `FileHandle.availableData` polling.
- Added bounded response timeouts so a failed refresh can clear `isRefreshing` and later refreshes can continue.
- Moved child process termination and `waitUntilExit()` off the main refresh path, with SIGKILL fallback after a short grace period.
- Documented the refresh liveness model in `README.md` and `ARCHITECTURE.md`.
