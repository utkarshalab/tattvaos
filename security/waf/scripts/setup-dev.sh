#!/usr/bin/env bash
# security/waf/scripts/setup-dev.sh — Set up development environment for WAF
set -euo pipefail

echo "[waf] Setting up development environment..."

if ! command -v nasm &>/dev/null; then
    echo "[waf] NASM not found. Install NASM to build .asm modules."
    echo "  Ubuntu/Debian: sudo apt-get install nasm"
    echo "  macOS:         brew install nasm"
    echo "  Windows (WSL): sudo apt-get install nasm"
    exit 1
fi

echo "[waf] NASM found: $(nasm -v)"
echo "[waf] Development environment ready."
echo "[waf] Run: make -C security/waf all && make -C security/waf test"
