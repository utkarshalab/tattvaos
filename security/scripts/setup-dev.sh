#!/usr/bin/env bash
# security/scripts/setup-dev.sh — Set up development environment for security stack
set -euo pipefail

echo "[security] Setting up development environment..."

# Check for NASM
if ! command -v nasm &>/dev/null; then
    echo "[security] NASM not found. Install NASM to build .asm modules."
    echo "  Ubuntu/Debian: sudo apt-get install nasm"
    echo "  macOS:         brew install nasm"
    echo "  Windows (WSL): sudo apt-get install nasm"
    exit 1
fi

echo "[security] NASM found: $(nasm -v)"
echo "[security] Development environment ready."
echo "[security] Run: make -C security all && make -C security test"
