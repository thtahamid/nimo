#!/usr/bin/env bash
set -euo pipefail

# Default configuration
CONFIG="Release"

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --configuration)
      CONFIG="${2:-}"
      if [[ -z "$CONFIG" ]]; then
        echo "error: --configuration requires a value (Release|Debug)" >&2
        exit 2
      fi
      shift 2
      ;;
    -h|--help)
      echo "Usage: $0 [--configuration Release|Debug]"
      exit 0
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

if [[ "$CONFIG" != "Release" && "$CONFIG" != "Debug" ]]; then
  echo "error: --configuration must be Release or Debug (got '$CONFIG')" >&2
  exit 2
fi

# Resolve repo root from script location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "==> Repo root: $REPO_ROOT"
echo "==> Configuration: $CONFIG"

# 1. Build the universal dylib
echo "==> Building nimo.dylib"
make -C "$REPO_ROOT/macos/dylib" clean all

# 2. Generate Xcode project via XcodeGen
echo "==> Generating Xcode project"
if ! command -v xcodegen >/dev/null 2>&1; then
  echo "error: xcodegen not found on PATH -- run 'brew install xcodegen' or './macos/scripts/ci-bootstrap.sh'" >&2
  exit 1
fi
(cd "$REPO_ROOT/macos/installer" && xcodegen generate)

# 3. Build the installer app
DERIVED_DATA="$REPO_ROOT/build/DerivedData"
echo "==> Building Nimo.app ($CONFIG) -> $DERIVED_DATA"
xcodebuild \
  -project "$REPO_ROOT/macos/installer/NimoInstaller.xcodeproj" \
  -scheme Nimo \
  -configuration "$CONFIG" \
  -derivedDataPath "$DERIVED_DATA" \
  -destination "generic/platform=macOS" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  build

# 4. Copy the .app into a predictable output location
OUT_DIR="$REPO_ROOT/build/$CONFIG"
mkdir -p "$OUT_DIR"
BUILT_APP="$DERIVED_DATA/Build/Products/$CONFIG/Nimo.app"

if [[ ! -d "$BUILT_APP" ]]; then
  echo "error: expected built app not found at $BUILT_APP" >&2
  exit 1
fi

rm -rf "$OUT_DIR/Nimo.app"
cp -R "$BUILT_APP" "$OUT_DIR/Nimo.app"

echo "==> Artifact: $OUT_DIR/Nimo.app"
