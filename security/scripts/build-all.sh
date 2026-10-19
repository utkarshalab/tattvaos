#!/usr/bin/env bash
# security/scripts/build-all.sh — Build all security modules
set -euo pipefail

cd "$(dirname "$0")/.."
make all
