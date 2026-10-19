#!/usr/bin/env bash
# security/waf/scripts/test.sh — Test WAF module
set -euo pipefail

cd "$(dirname "$0")/.."
make test
