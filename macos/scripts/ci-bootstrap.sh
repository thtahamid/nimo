#!/usr/bin/env bash
set -euo pipefail

if ! command -v brew >/dev/null 2>&1; then
  echo "error: Homebrew not found on PATH" >&2
  exit 1
fi

install_if_missing() {
  local pkg="$1"
  if brew list "$pkg" &>/dev/null; then
    echo "==> $pkg already installed"
  else
    echo "==> installing $pkg"
    brew install "$pkg"
  fi
}

install_if_missing xcodegen
install_if_missing create-dmg

echo "==> ci-bootstrap complete"
