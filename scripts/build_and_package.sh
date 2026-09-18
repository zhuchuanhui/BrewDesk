#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

TAG_NAME="${1:-${GITHUB_REF_NAME:-$(git describe --tags --exact-match 2>/dev/null || true)}}"
if [[ -z "$TAG_NAME" ]]; then
  echo "タグを指定してください（例: $0 v1.0.0）" >&2
  exit 1
fi

VERSION="${TAG_NAME#v}"
if [[ "$VERSION" != "$TAG_NAME" && "$TAG_NAME" != v* ]]; then
  echo "タグは v1.2.3 形式で指定してください: $TAG_NAME" >&2
  exit 1
fi
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "タグは v1.2.3 形式で指定してください: $TAG_NAME" >&2
  exit 1
fi

APP_NAME="BrewDesk"
BUILD_DIR="$ROOT_DIR/.build/release"
OUTPUT_DIR="$ROOT_DIR/outputs"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
DMG_PATH="$OUTPUT_DIR/${APP_NAME}-${VERSION}.dmg"

rm -rf "$APP_DIR"
mkdir -p "$OUTPUT_DIR" "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

BIN_PATH="$(swift build -c release --product "$APP_NAME" --show-bin-path)/$APP_NAME"
cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp "$ROOT_DIR/work/Info.plist" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$APP_DIR/Contents/Info.plist"
chmod +x "$APP_DIR/Contents/MacOS/$APP_NAME"

rm -f "$DMG_PATH"
hdiutil create -volname "$APP_NAME $VERSION" -srcfolder "$APP_DIR" -ov -format UDZO "$DMG_PATH" >/dev/null

echo "アプリ: $APP_DIR"
echo "DMG:   $DMG_PATH"
echo "Version: $VERSION"
