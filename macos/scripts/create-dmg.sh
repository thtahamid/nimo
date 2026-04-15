#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-1.0.0-dev}"

# Resolve repo root from script location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

APP="$REPO_ROOT/build/Release/Nimo.app"
if [[ ! -d "$APP" ]]; then
  echo "error: $APP not found -- run macos/scripts/build.sh first" >&2
  exit 1
fi

if ! command -v create-dmg >/dev/null 2>&1; then
  echo "error: create-dmg not found on PATH -- run 'brew install create-dmg' or './macos/scripts/ci-bootstrap.sh'" >&2
  exit 1
fi

DMG_DIR="$REPO_ROOT/build/dmg"
mkdir -p "$DMG_DIR"

DMG="$DMG_DIR/Nimo-$VERSION.dmg"
rm -f "$DMG"

echo "==> Creating DMG: $DMG"
create-dmg \
  --volname "Nimo Installer" \
  --window-pos 200 120 \
  --window-size 600 400 \
  --icon-size 100 \
  --icon "Nimo.app" 150 190 \
  --app-drop-link 450 185 \
  --no-internet-enable \
  "$DMG" \
  "$APP"

# Emit SHA-256 next to the DMG
SHA_FILE="$DMG_DIR/Nimo-$VERSION.sha256"
(cd "$DMG_DIR" && shasum -a 256 "Nimo-$VERSION.dmg" > "$SHA_FILE")

echo "==> DMG:    $DMG"
echo "==> SHA256: $SHA_FILE"
