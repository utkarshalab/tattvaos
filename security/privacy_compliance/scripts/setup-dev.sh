#!/usr/bin/env bash
# security/privacy_compliance/scripts/setup-dev.sh — development environment setup
set -euo pipefail

cd "$(dirname "$0")/.."

echo "[privacy_compliance] Setting up development environment..."

if ! command -v nasm &>/dev/null; then
    echo "ERROR: nasm is not installed."
    exit 1
fi

echo "  NASM: $(nasm -v | head -1)"

if ! command -v make &>/dev/null; then
    echo "ERROR: make is not installed."
    exit 1
fi

mkdir -p bin build

echo ""
echo "[privacy_compliance] Development environment ready."
echo "  Build:   make -C security/privacy_compliance"
echo "  Test:    make -C security/privacy_compliance test"
echo "  Clean:   make -C security/privacy_compliance clean"