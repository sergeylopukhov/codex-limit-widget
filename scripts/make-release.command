#!/bin/zsh
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="Release"
VERSION="1.1.2"
APP_NAME="Codex Limit Widget.app"
BUILT_APP="$PROJECT_DIR/build/DerivedData/Build/Products/$CONFIGURATION/$APP_NAME"
BUILT_APPEX="$PROJECT_DIR/build/DerivedData/Build/Products/$CONFIGURATION/CodexLimitWidgetExtension.appex"
RELEASE_DIR="$PROJECT_DIR/release/CodexLimitWidget-$VERSION"
ZIP_PATH="$PROJECT_DIR/release/CodexLimitWidget-$VERSION-macOS.zip"
DMG_STAGING_DIR="$PROJECT_DIR/release/CodexLimitWidget-$VERSION-dmg"
DMG_PATH="$PROJECT_DIR/release/CodexLimitWidget-$VERSION-macOS.dmg"
DMG_TEMP_PATH="$PROJECT_DIR/release/CodexLimitWidget-$VERSION-macOS-rw.dmg"
DMG_VOLUME_NAME="Codex Limit Widget $VERSION"
DMG_BACKGROUND="$DMG_STAGING_DIR/.background/background.png"

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

rm -rf "$RELEASE_DIR" "$ZIP_PATH" "$DMG_STAGING_DIR" "$DMG_PATH" "$DMG_TEMP_PATH"
mkdir -p "$RELEASE_DIR"
cp -R "$BUILT_APP" "$RELEASE_DIR/$APP_NAME"

codesign --force --sign - \
  --entitlements "$PROJECT_DIR/CodexLimitWidgetExtension/CodexLimitWidgetExtension.entitlements" \
  "$RELEASE_DIR/$APP_NAME/Contents/PlugIns/CodexLimitWidgetExtension.appex"
codesign --force --sign - \
  --entitlements "$PROJECT_DIR/CodexLimitWidgetApp/CodexLimitWidgetApp.entitlements" \
  "$RELEASE_DIR/$APP_NAME"

mkdir -p "$DMG_STAGING_DIR"
cp -R "$RELEASE_DIR/$APP_NAME" "$DMG_STAGING_DIR/$APP_NAME"
ln -s /Applications "$DMG_STAGING_DIR/Applications"
mkdir -p "$DMG_STAGING_DIR/.background"

swift /dev/stdin "$DMG_BACKGROUND" <<'SWIFT'
import AppKit

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let size = NSSize(width: 660, height: 400)
let image = NSImage(size: size)

image.lockFocus()

NSColor(calibratedRed: 0.965, green: 0.972, blue: 0.980, alpha: 1).setFill()
NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()

let title = "Drag to Applications"
let titleAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 24, weight: .semibold),
    .foregroundColor: NSColor(calibratedWhite: 0.14, alpha: 1)
]
let titleSize = title.size(withAttributes: titleAttributes)
title.draw(
    at: NSPoint(x: (size.width - titleSize.width) / 2, y: 326),
    withAttributes: titleAttributes
)

let subtitle = "Install Codex Limit Widget"
let subtitleAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 14, weight: .regular),
    .foregroundColor: NSColor(calibratedWhite: 0.42, alpha: 1)
]
let subtitleSize = subtitle.size(withAttributes: subtitleAttributes)
subtitle.draw(
    at: NSPoint(x: (size.width - subtitleSize.width) / 2, y: 300),
    withAttributes: subtitleAttributes
)

let arrowColor = NSColor(calibratedRed: 0.12, green: 0.45, blue: 0.88, alpha: 1)
arrowColor.setStroke()
arrowColor.setFill()

let arrow = NSBezierPath()
arrow.lineWidth = 8
arrow.lineCapStyle = .round
arrow.move(to: NSPoint(x: 250, y: 190))
arrow.line(to: NSPoint(x: 410, y: 190))
arrow.stroke()

let head = NSBezierPath()
head.move(to: NSPoint(x: 420, y: 190))
head.line(to: NSPoint(x: 390, y: 212))
head.line(to: NSPoint(x: 390, y: 168))
head.close()
head.fill()

let hint = "Drop here"
let hintAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 13, weight: .medium),
    .foregroundColor: NSColor(calibratedWhite: 0.36, alpha: 1)
]
let hintSize = hint.size(withAttributes: hintAttributes)
hint.draw(at: NSPoint(x: 500 - hintSize.width / 2, y: 105), withAttributes: hintAttributes)

image.unlockFocus()

guard
    let tiff = image.tiffRepresentation,
    let bitmap = NSBitmapImageRep(data: tiff),
    let png = bitmap.representation(using: .png, properties: [:])
else {
    fatalError("Failed to render DMG background")
}

try png.write(to: outputURL)
SWIFT
chflags hidden "$DMG_STAGING_DIR/.background"

COPYFILE_DISABLE=1 hdiutil create \
  -volname "$DMG_VOLUME_NAME" \
  -srcfolder "$DMG_STAGING_DIR" \
  -ov \
  -format UDRW \
  "$DMG_TEMP_PATH"

MOUNT_DIR="$(hdiutil attach "$DMG_TEMP_PATH" -readwrite -noverify -noautoopen | sed -n 's|^.*\(/Volumes/.*\)$|\1|p' | tail -1)"
if [[ -z "$MOUNT_DIR" ]]; then
  echo "Failed to mount DMG for layout" >&2
  exit 1
fi

osascript <<APPLESCRIPT
tell application "Finder"
  tell disk "$DMG_VOLUME_NAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set bounds of container window to {120, 120, 780, 520}
    set theViewOptions to icon view options of container window
    set arrangement of theViewOptions to not arranged
    set icon size of theViewOptions to 96
    set background picture of theViewOptions to POSIX file "$MOUNT_DIR/.background/background.png"
    set position of item "$APP_NAME" of container window to {170, 215}
    set position of item "Applications" of container window to {500, 215}
    update without registering applications
    delay 1
    close
  end tell
end tell
APPLESCRIPT

hdiutil detach "$MOUNT_DIR"

COPYFILE_DISABLE=1 hdiutil convert "$DMG_TEMP_PATH" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -o "$DMG_PATH"

COPYFILE_DISABLE=1 ditto -c -k --norsrc --keepParent "$RELEASE_DIR" "$ZIP_PATH"
codesign --verify --deep --strict --verbose=2 "$RELEASE_DIR/$APP_NAME"
rm -rf "$DMG_STAGING_DIR" "$DMG_TEMP_PATH" "$RELEASE_DIR" "$BUILT_APP" "$BUILT_APPEX"

echo "$DMG_PATH"
echo "$ZIP_PATH"
