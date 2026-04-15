#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <version>" >&2
  exit 2
fi

VERSION="$1"

# Basic sanity check: semver-ish (allow pre-release suffixes)
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9.-]+)?$ ]]; then
  echo "error: version '$VERSION' does not look like semver (e.g. 1.2.3 or 1.2.3-beta.1)" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

INSTALLER_PLIST="$REPO_ROOT/macos/installer/Sources/Resources/Info.plist"
PROJECT_YML="$REPO_ROOT/macos/installer/project.yml"
DYLIB_PLIST="$REPO_ROOT/macos/dylib/Info.plist"

PLISTBUDDY="/usr/libexec/PlistBuddy"
if [[ ! -x "$PLISTBUDDY" ]]; then
  echo "error: PlistBuddy not found at $PLISTBUDDY (this script requires macOS)" >&2
  exit 1
fi

update_plist() {
  local plist="$1"
  if [[ ! -f "$plist" ]]; then
    echo "warn: plist not found at $plist -- skipping" >&2
    return 0
  fi
  # CFBundleShortVersionString
  if "$PLISTBUDDY" -c "Print :CFBundleShortVersionString" "$plist" >/dev/null 2>&1; then
    "$PLISTBUDDY" -c "Set :CFBundleShortVersionString $VERSION" "$plist"
  else
    "$PLISTBUDDY" -c "Add :CFBundleShortVersionString string $VERSION" "$plist"
  fi
  # CFBundleVersion
  if "$PLISTBUDDY" -c "Print :CFBundleVersion" "$plist" >/dev/null 2>&1; then
    "$PLISTBUDDY" -c "Set :CFBundleVersion $VERSION" "$plist"
  else
    "$PLISTBUDDY" -c "Add :CFBundleVersion string $VERSION" "$plist"
  fi
  echo "==> Updated $plist"
}

update_plist "$INSTALLER_PLIST"
update_plist "$DYLIB_PLIST"

if [[ -f "$PROJECT_YML" ]]; then
  # BSD sed (macOS) requires the empty '' after -i
  sed -i '' -E "s/^([[:space:]]*MARKETING_VERSION:[[:space:]]*).*/\1$VERSION/" "$PROJECT_YML"
  echo "==> Updated MARKETING_VERSION in $PROJECT_YML"
else
  echo "warn: $PROJECT_YML not found -- skipping" >&2
fi

echo "$VERSION"
