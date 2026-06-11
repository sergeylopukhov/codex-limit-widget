#!/bin/zsh
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="Release"
VERSION="1.0.0"
APP_NAME="Codex Limit Widget.app"
BUILT_APP="$PROJECT_DIR/build/DerivedData/Build/Products/$CONFIGURATION/$APP_NAME"
RELEASE_DIR="$PROJECT_DIR/release/CodexLimitWidget-$VERSION"
ZIP_PATH="$PROJECT_DIR/release/CodexLimitWidget-$VERSION-macOS.zip"

cd "$PROJECT_DIR"
mkdir -p build outputs release
touch build/.metadata_never_index outputs/.metadata_never_index

xcodebuild \
  -project CodexLimitWidget.xcodeproj \
  -scheme CodexLimitWidget \
  -configuration "$CONFIGURATION" \
  -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build

rm -rf "$RELEASE_DIR" "$ZIP_PATH"
mkdir -p "$RELEASE_DIR"
cp -R "$BUILT_APP" "$RELEASE_DIR/$APP_NAME"
cp scripts/install.command "$RELEASE_DIR/install.command"
chmod +x "$RELEASE_DIR/install.command"

codesign --force --sign - \
  --entitlements "$PROJECT_DIR/CodexLimitWidgetExtension/CodexLimitWidgetExtension.entitlements" \
  "$RELEASE_DIR/$APP_NAME/Contents/PlugIns/CodexLimitWidgetExtension.appex"
codesign --force --sign - \
  --entitlements "$PROJECT_DIR/CodexLimitWidgetApp/CodexLimitWidgetApp.entitlements" \
  "$RELEASE_DIR/$APP_NAME"

COPYFILE_DISABLE=1 ditto -c -k --norsrc --keepParent "$RELEASE_DIR" "$ZIP_PATH"
codesign --verify --deep --strict --verbose=2 "$RELEASE_DIR/$APP_NAME"

echo "$ZIP_PATH"
