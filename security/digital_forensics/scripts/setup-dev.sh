#!/usr/bin/env bash
# security/digital_forensics/scripts/setup-dev.sh — development environment setup
set -euo pipefail

cd "$(dirname "$0")/.."

echo "[digital_forensics] Setting up development environment..."

if ! command -v nasm &>/dev/null; then
    echo "ERROR: nasm is not installed."
    echo "  Debian/Ubuntu: sudo apt-get install nasm"
    echo "  RHEL/CentOS:   sudo yum install nasm"
    echo "  macOS:         brew install nasm"
    exit 1
fi

echo "  NASM: $(nasm -v | head -1)"

if ! command -v make &>/dev/null; then
    echo "ERROR: make is not installed."
    exit 1
fi

mkdir -p bin build

echo ""
echo "[digital_forensics] Development environment ready."
echo "  Build:   make -C security/digital_forensics"
echo "  Test:    make -C security/digital_forensics test"
echo "  Clean:   make -C security/digital_forensics clean"