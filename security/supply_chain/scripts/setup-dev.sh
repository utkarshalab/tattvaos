#!/usr/bin/env bash
# security/supply_chain/scripts/setup-dev.sh — development environment setup
set -euo pipefail

cd "$(dirname "$0")/.."

echo "[supply_chain] Setting up development environment..."

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
echo "[supply_chain] Development environment ready."
echo "  Build:   make -C security/supply_chain"
echo "  Test:    make -C security/supply_chain test"
echo "  Clean:   make -C security/supply_chain clean"