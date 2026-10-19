#!/usr/bin/env bash
# security/ids/scripts/build.sh — Build IDS module
set -euo pipefail

cd "$(dirname "$0")/.."
make all
