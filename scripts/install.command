#!/bin/zsh
set -euo pipefail

APP_NAME="Codex Limit Widget.app"
SOURCE_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_APP="$SOURCE_DIR/$APP_NAME"
TARGET_APP="/Applications/$APP_NAME"
OLD_TARGET_APP="/Applications/CodexLimitWidget.app"
PREVIOUS_TARGET_APP="/Applications/Codex Limit.app"
EXTENSION_APP="$TARGET_APP/Contents/PlugIns/Codex Limit Widget Extension.appex"
OLD_EXTENSION_APP="$TARGET_APP/Contents/PlugIns/CodexLimitWidgetExtension.appex"

if [ ! -d "$SOURCE_APP" ]; then
  osascript -e 'display alert "Codex Limit Widget" message "Codex Limit Widget.app was not found next to install.command."'
  exit 1
fi

pkill -x "Codex Limit Widget" 2>/dev/null || true
pkill -x "Codex Limit" 2>/dev/null || true
pkill -x CodexLimitWidget 2>/dev/null || true
pkill -f "Codex Limit Widget Extension.appex" 2>/dev/null || true
pkill -f "CodexLimitWidgetExtension.appex" 2>/dev/null || true

if [ -d "$EXTENSION_APP" ]; then
  pluginkit -r "$EXTENSION_APP" 2>/dev/null || true
fi
if [ -d "$OLD_EXTENSION_APP" ]; then
  pluginkit -r "$OLD_EXTENSION_APP" 2>/dev/null || true
fi
rm -rf "$TARGET_APP" "$OLD_TARGET_APP" "$PREVIOUS_TARGET_APP"
cp -R "$SOURCE_APP" "$TARGET_APP"
xattr -dr com.apple.quarantine "$TARGET_APP" 2>/dev/null || true

/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$OLD_TARGET_APP" 2>/dev/null || true
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$PREVIOUS_TARGET_APP" 2>/dev/null || true
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f -R "$TARGET_APP"
pluginkit -a "$EXTENSION_APP" 2>/dev/null || true
touch "$TARGET_APP" "$EXTENSION_APP" 2>/dev/null || true
rm -rf "$HOME/Library/Caches/com.apple.chrono/widget-relevance-cache" 2>/dev/null || true
/usr/bin/qlmanage -r cache >/dev/null 2>&1 || true
killall iconservicesagent 2>/dev/null || true
killall IconServicesAgent 2>/dev/null || true
killall chronod 2>/dev/null || true
killall NotificationCenter 2>/dev/null || true
killall WidgetKitExtension 2>/dev/null || true
killall Dock 2>/dev/null || true

open "$TARGET_APP"
osascript -e 'display notification "Installed and launched" with title "Codex Limit Widget"'
