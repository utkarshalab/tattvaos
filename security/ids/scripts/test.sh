#!/usr/bin/env bash
# security/ids/scripts/test.sh — Test IDS module
set -euo pipefail

cd "$(dirname "$0")/.."
make test
