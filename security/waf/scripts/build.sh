#!/usr/bin/env bash
# security/waf/scripts/build.sh — Build WAF module
set -euo pipefail

cd "$(dirname "$0")/.."
make all
