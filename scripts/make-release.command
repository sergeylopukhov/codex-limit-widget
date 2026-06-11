#!/bin/zsh
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="Release"
VERSION="1.0.1"
APP_NAME="Codex Limit Widget.app"
BUILT_APP="$PROJECT_DIR/build/DerivedData/Build/Products/$CONFIGURATION/$APP_NAME"
RELEASE_DIR="$PROJECT_DIR/release/CodexLimitWidget-$VERSION"
ZIP_PATH="$PROJECT_DIR/release/CodexLimitWidget-$VERSION-macOS.zip"
DMG_STAGING_DIR="$PROJECT_DIR/release/CodexLimitWidget-$VERSION-dmg"
DMG_PATH="$PROJECT_DIR/release/CodexLimitWidget-$VERSION-macOS.dmg"

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

rm -rf "$RELEASE_DIR" "$ZIP_PATH" "$DMG_STAGING_DIR" "$DMG_PATH"
mkdir -p "$RELEASE_DIR"
cp -R "$BUILT_APP" "$RELEASE_DIR/$APP_NAME"
cp scripts/install.command "$RELEASE_DIR/install.command"
chmod +x "$RELEASE_DIR/install.command"

codesign --force --sign - \
  --entitlements "$PROJECT_DIR/CodexLimitWidgetExtension/CodexLimitWidgetExtension.entitlements" \
  "$RELEASE_DIR/$APP_NAME/Contents/PlugIns/Codex Limit Widget Extension.appex"
codesign --force --sign - \
  --entitlements "$PROJECT_DIR/CodexLimitWidgetApp/CodexLimitWidgetApp.entitlements" \
  "$RELEASE_DIR/$APP_NAME"

mkdir -p "$DMG_STAGING_DIR"
cp -R "$RELEASE_DIR/$APP_NAME" "$DMG_STAGING_DIR/$APP_NAME"
cp "$RELEASE_DIR/install.command" "$DMG_STAGING_DIR/install.command"
ln -s /Applications "$DMG_STAGING_DIR/Applications"

COPYFILE_DISABLE=1 hdiutil create \
  -volname "Codex Limit Widget $VERSION" \
  -srcfolder "$DMG_STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

COPYFILE_DISABLE=1 ditto -c -k --norsrc --keepParent "$RELEASE_DIR" "$ZIP_PATH"
codesign --verify --deep --strict --verbose=2 "$RELEASE_DIR/$APP_NAME"
rm -rf "$DMG_STAGING_DIR"

echo "$DMG_PATH"
echo "$ZIP_PATH"
