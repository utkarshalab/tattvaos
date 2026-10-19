#!/usr/bin/env bash
# security/threat_intel/scripts/setup-dev.sh — development environment setup
set -euo pipefail

cd "$(dirname "$0")/.."

echo "[threat_intel] Setting up development environment..."

# Verify NASM is available
if ! command -v nasm &>/dev/null; then
    echo "ERROR: nasm is not installed. Please install nasm first."
    echo "  Debian/Ubuntu: sudo apt-get install nasm"
    echo "  RHEL/CentOS:   sudo yum install nasm"
    echo "  macOS:         brew install nasm"
    exit 1
fi

NASM_VERSION=$(nasm -v | head -1)
echo "  NASM: $NASM_VERSION"

# Verify make is available
if ! command -v make &>/dev/null; then
    echo "ERROR: make is not installed."
    exit 1
fi

# Create bin directory if needed
mkdir -p bin build

echo ""
echo "[threat_intel] Development environment ready."
echo ""
echo "  Build:   make -C security/threat_intel"
echo "  Test:    make -C security/threat_intel test"
echo "  Clean:   make -C security/threat_intel clean"