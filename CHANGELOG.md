# Changelog

## 1.1.7

- Fixed weekly-only accounts where the 7-day window is returned as `primary` and was incorrectly labeled as a 5-hour limit.
- Removed all 5-hour labels and choices from the runtime UI when the account has no 5-hour limit.
- Filled the empty dark-widget area for weekly-only accounts with weekly usage, progress, and reset details.

## 1.1.6

- Fixed refreshes for accounts where Codex no longer returns a 5-hour limit window.
- Kept the weekly limit visible in the app and widgets when the 5-hour window is unavailable.

## 1.1.5

- Added a dedicated weekly reset date and time line to the menu bar popover.
- Increased the popover height so the weekly reset line stays visible above Settings.

## 1.1.4

- Preserved usage stats between refreshes when Codex rate-limit data updates but usage details are temporarily unavailable.

## 1.1.3

- Consolidated WidgetKit copy around one widget: `Codex Limit Widget`, available in Small, Medium, and Large sizes.
- Clarified that `Window design` controls the visual theme for the app, popover, and already-added widgets.
- Documented that switching between `Dark` and `Beige` updates widgets through shared app settings.

## 1.1.2

- Added shared app styling for the settings window and menu bar popover.
- Prepared the app description and screenshots for the unified `Dark` and `Beige` window design model.

## 1.1.1

- Tightened the widget layouts for Beige window design: smaller small-widget title, small-widget `PLAN` stat instead of repeated weekly stat, and higher large-widget percent block.
- Removed the duplicate plan label from the large-widget message area and shortened the status message to avoid truncation.

## 1.1.0

- Added the Beige window design presentation using paper tones, serif typography, thin dividers, and muted progress bars.
- Kept the widget data source unchanged: the widget reads the same cached Codex limit snapshot.
- Made the Beige progress bar explicitly show the weekly limit, removed request counts, and show the exact 5-hour reset time.

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
