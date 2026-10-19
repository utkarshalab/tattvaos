#!/usr/bin/env bash
# security/vuln_scan/scripts/setup-dev.sh — development environment setup
set -euo pipefail

cd "$(dirname "$0")/.."

echo "[vuln_scan] Setting up development environment..."

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
echo "[vuln_scan] Development environment ready."
echo "  Build:   make -C security/vuln_scan"
echo "  Test:    make -C security/vuln_scan test"
echo "  Clean:   make -C security/vuln_scan clean"