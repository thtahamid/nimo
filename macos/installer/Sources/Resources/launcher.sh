#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
export DYLD_INSERT_LIBRARIES="$SCRIPT_DIR/nimo.dylib"
exec "$SCRIPT_DIR/Discord.real" "$@"
