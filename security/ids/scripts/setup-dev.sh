#!/usr/bin/env bash
# security/ids/scripts/setup-dev.sh — Set up development environment for IDS
set -euo pipefail

echo "[ids] Setting up development environment..."

if ! command -v nasm &>/dev/null; then
    echo "[ids] NASM not found. Install NASM to build .asm modules."
    echo "  Ubuntu/Debian: sudo apt-get install nasm"
    echo "  macOS:         brew install nasm"
    echo "  Windows (WSL): sudo apt-get install nasm"
    exit 1
fi

echo "[ids] NASM found: $(nasm -v)"
echo "[ids] Development environment ready."
echo "[ids] Run: make -C security/ids all && make -C security/ids test"
