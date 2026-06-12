# Changelog

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
