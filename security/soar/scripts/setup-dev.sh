#!/usr/bin/env bash
# security/soar/scripts/setup-dev.sh — Set up development environment for SOAR
set -euo pipefail

echo "[soar] Setting up development environment..."

if ! command -v nasm &>/dev/null; then
    echo "[soar] NASM not found. Install NASM to build .asm modules."
    echo "  Ubuntu/Debian: sudo apt-get install nasm"
    echo "  macOS:         brew install nasm"
    echo "  Windows (WSL): sudo apt-get install nasm"
    exit 1
fi

echo "[soar] NASM found: $(nasm -v)"
echo "[soar] Development environment ready."
echo "[soar] Run: make -C security/soar all && make -C security/soar test"
