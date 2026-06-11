#!/bin/zsh
set -euo pipefail

APP_NAME="Codex Limit Widget.app"
SOURCE_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_APP="$SOURCE_DIR/$APP_NAME"
TARGET_APP="/Applications/$APP_NAME"
OLD_TARGET_APP="/Applications/CodexLimitWidget.app"
PREVIOUS_TARGET_APP="/Applications/Codex Limit.app"

if [ ! -d "$SOURCE_APP" ]; then
  osascript -e 'display alert "Codex Limit Widget" message "Codex Limit Widget.app was not found next to install.command."'
  exit 1
fi

pkill -x "Codex Limit Widget" 2>/dev/null || true
pkill -x "Codex Limit" 2>/dev/null || true
pkill -x CodexLimitWidget 2>/dev/null || true
pkill -f "CodexLimitWidgetExtension.appex" 2>/dev/null || true

rm -rf "$TARGET_APP" "$OLD_TARGET_APP" "$PREVIOUS_TARGET_APP"
cp -R "$SOURCE_APP" "$TARGET_APP"
xattr -dr com.apple.quarantine "$TARGET_APP" 2>/dev/null || true

/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$OLD_TARGET_APP" 2>/dev/null || true
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$PREVIOUS_TARGET_APP" 2>/dev/null || true
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f -R "$TARGET_APP"

open "$TARGET_APP"
osascript -e 'display notification "Installed and launched" with title "Codex Limit Widget"'
