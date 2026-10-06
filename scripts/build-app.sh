#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

BUILD_DIR="$ROOT/.build"
APP_DIR="$ROOT/AutoClicker.app"
CONTENTS="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES_DIR="$CONTENTS/Resources"

echo "Building AutoClicker (release)..."
swift build -c release --product AutoClicker

BINARY="$(swift build -c release --show-bin-path)/AutoClicker"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$BINARY" "$MACOS_DIR/AutoClicker"
cp "$ROOT/Sources/AutoClicker/Info.plist" "$CONTENTS/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"

chmod +x "$MACOS_DIR/AutoClicker"

echo "Signing..."
IDENTITY="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Apple Development:.*\)"/\1/p' | head -1)"
if [[ -n "$IDENTITY" ]]; then
  codesign --force --sign "$IDENTITY" "$APP_DIR"
else
  echo "No Apple Development identity found; ad-hoc signing."
  echo "Accessibility must be granted again after every rebuild."
  codesign --force --sign - "$APP_DIR"
fi

echo "Built: $APP_DIR"

if [[ "${1:-}" == "--open" ]]; then
  open "$APP_DIR"
fi
