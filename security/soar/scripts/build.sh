#!/usr/bin/env bash
# security/soar/scripts/build.sh — Build SOAR module
set -euo pipefail

cd "$(dirname "$0")/.."
make all
