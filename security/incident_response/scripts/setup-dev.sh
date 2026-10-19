#!/usr/bin/env bash
# security/incident_response/scripts/setup-dev.sh — development environment setup
set -euo pipefail

cd "$(dirname "$0")/.."

echo "[incident_response] Setting up development environment..."

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
echo "[incident_response] Development environment ready."
echo "  Build:   make -C security/incident_response"
echo "  Test:    make -C security/incident_response test"
echo "  Clean:   make -C security/incident_response clean"