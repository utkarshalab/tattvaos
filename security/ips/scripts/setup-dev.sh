#!/usr/bin/env bash
# security/ips/scripts/setup-dev.sh — Set up development environment for IPS
set -euo pipefail

echo "[ips] Setting up development environment..."

if ! command -v nasm &>/dev/null; then
    echo "[ips] NASM not found. Install NASM to build .asm modules."
    echo "  Ubuntu/Debian: sudo apt-get install nasm"
    echo "  macOS:         brew install nasm"
    echo "  Windows (WSL): sudo apt-get install nasm"
    exit 1
fi

echo "[ips] NASM found: $(nasm -v)"
echo "[ips] Development environment ready."
echo "[ips] Run: make -C security/ips all && make -C security/ips test"
