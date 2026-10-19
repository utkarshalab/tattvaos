#!/usr/bin/env bash
# security/scripts/test-all.sh — Run all security module tests
set -euo pipefail

cd "$(dirname "$0")/.."
make test
