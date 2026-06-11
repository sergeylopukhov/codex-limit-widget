#!/bin/zsh
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Codex Limit Widget.app"
CONFIGURATION="Release"
BUILT_APP="$PROJECT_DIR/build/DerivedData/Build/Products/$CONFIGURATION/$APP_NAME"
TARGET_APP="/Applications/$APP_NAME"
OLD_TARGET_APP="/Applications/CodexLimitWidget.app"
PREVIOUS_TARGET_APP="/Applications/Codex Limit.app"
EXTENSION_APP="$TARGET_APP/Contents/PlugIns/Codex Limit Widget Extension.appex"
OLD_EXTENSION_APP="$TARGET_APP/Contents/PlugIns/CodexLimitWidgetExtension.appex"

cd "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR/build" "$PROJECT_DIR/outputs"
touch "$PROJECT_DIR/build/.metadata_never_index" "$PROJECT_DIR/outputs/.metadata_never_index"

xcodebuild \
  -project CodexLimitWidget.xcodeproj \
  -scheme CodexLimitWidget \
  -configuration "$CONFIGURATION" \
  -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build

pkill -x "Codex Limit Widget" 2>/dev/null || true
pkill -x "Codex Limit" 2>/dev/null || true
pkill -x CodexLimitWidget 2>/dev/null || true
pkill -f "Codex Limit Widget Extension.appex" 2>/dev/null || true
pkill -f "CodexLimitWidgetExtension.appex" 2>/dev/null || true
sleep 1

/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$OLD_TARGET_APP" 2>/dev/null || true
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$PREVIOUS_TARGET_APP" 2>/dev/null || true
if [ -d "$EXTENSION_APP" ]; then
  pluginkit -r "$EXTENSION_APP" 2>/dev/null || true
fi
if [ -d "$OLD_EXTENSION_APP" ]; then
  pluginkit -r "$OLD_EXTENSION_APP" 2>/dev/null || true
fi
rm -rf "$TARGET_APP"
rm -rf "$OLD_TARGET_APP"
rm -rf "$PREVIOUS_TARGET_APP"
cp -R "$BUILT_APP" "$TARGET_APP"
xattr -dr com.apple.quarantine "$TARGET_APP" 2>/dev/null || true
codesign --force --sign - \
  --entitlements "$PROJECT_DIR/CodexLimitWidgetExtension/CodexLimitWidgetExtension.entitlements" \
  "$EXTENSION_APP"
codesign --force --sign - \
  --entitlements "$PROJECT_DIR/CodexLimitWidgetApp/CodexLimitWidgetApp.entitlements" \
  "$TARGET_APP"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f -R "$TARGET_APP"
pluginkit -a "$EXTENSION_APP" 2>/dev/null || true
touch "$TARGET_APP" "$EXTENSION_APP" 2>/dev/null || true
/usr/bin/qlmanage -r cache >/dev/null 2>&1 || true
killall iconservicesagent 2>/dev/null || true
killall IconServicesAgent 2>/dev/null || true
killall WidgetKitExtension 2>/dev/null || true
open "$TARGET_APP"

osascript -e 'display notification "Built, installed, and launched" with title "Codex Limit Widget"'
