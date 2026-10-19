#!/usr/bin/env bash
# security/ips/scripts/test.sh — Test IPS module
set -euo pipefail

cd "$(dirname "$0")/.."
make test
