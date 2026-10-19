#!/usr/bin/env bash
# security/soar/scripts/test.sh — Test SOAR module
set -euo pipefail

cd "$(dirname "$0")/.."
make test
