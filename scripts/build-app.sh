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

sign_app() {
  local p12=""
  local password=""
  local dir=""

  if [[ -n "${SIGNING_P12_BASE64:-}" && -n "${SIGNING_PASSWORD:-}" ]]; then
    dir="$(mktemp -d)"
    p12="$dir/signing.p12"
    printf '%s' "$SIGNING_P12_BASE64" | tr -d '[:space:]' | base64 -D > "$p12"
    if [[ ! -s "$p12" ]]; then
      echo "Could not decode the signing certificate." >&2
      exit 1
    fi
    password="$SIGNING_PASSWORD"
  elif [[ -f "$HOME/Library/Application Support/AutoClicker/signing/signing.p12" && -f "$HOME/Library/Application Support/AutoClicker/signing/password" ]]; then
    p12="$HOME/Library/Application Support/AutoClicker/signing/signing.p12"
    password="$(tr -d '\n' < "$HOME/Library/Application Support/AutoClicker/signing/password")"
  fi

  if [[ -n "$p12" ]]; then
    sign_with_p12 "$p12" "$password"
    return
  fi

  local identity
  identity="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application:.*\)"/\1/p' | head -1)"
  if [[ -z "$identity" ]]; then
    identity="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Apple Development:.*\)"/\1/p' | head -1)"
  fi
  if [[ -n "$identity" ]]; then
    codesign --force --sign "$identity" "$APP_DIR"
    echo "Signed with: $identity"
    return
  fi

  echo "No stable signing identity found; ad-hoc signing."
  echo "Accessibility must be granted again after every rebuild."
  codesign --force --sign - "$APP_DIR"
}

sign_with_p12() {
  local p12="$1"
  local password="$2"
  local dir keychain hash status=0
  local -a saved=()
  local line
  dir="$(mktemp -d)"
  keychain="$dir/signing.keychain-db"

  restore_keychains() {
    if [[ ${#saved[@]} -gt 0 ]]; then
      security list-keychains -s "${saved[@]}" >/dev/null 2>&1 || true
    fi
    if [[ -f "$keychain" ]]; then
      security delete-keychain "$keychain" >/dev/null 2>&1 || true
    fi
  }

  security create-keychain -p "$password" "$keychain"
  security set-keychain-settings "$keychain"
  security unlock-keychain -p "$password" "$keychain"
  security import "$p12" -k "$keychain" -P "$password" -T /usr/bin/codesign -A >/dev/null
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$password" "$keychain" >/dev/null || true

  while IFS= read -r line; do
    line="${line#*\"}"
    line="${line%\"*}"
    [[ -n "$line" ]] && saved+=("$line")
  done < <(security list-keychains)
  security list-keychains -s "$keychain" "${saved[@]}"

  hash="$(security find-certificate -c "Auto Clicker Signing" -Z "$keychain" | awk '/SHA-1 hash:/{print $3; exit}')"
  if [[ -z "$hash" ]]; then
    echo "Stable signing certificate could not be read; ad-hoc signing." >&2
    codesign --force --sign - "$APP_DIR" || status=$?
  else
    codesign --force --sign "$hash" --keychain "$keychain" "$APP_DIR" || status=$?
    if [[ "$status" -eq 0 ]]; then
      echo "Signed with the stable Auto Clicker identity."
    fi
  fi
  restore_keychains
  return "$status"
}

echo "Signing..."
sign_app

echo "Built: $APP_DIR"

if [[ "${1:-}" == "--open" ]]; then
  open "$APP_DIR"
fi
