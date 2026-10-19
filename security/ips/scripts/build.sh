#!/usr/bin/env bash
# security/ips/scripts/build.sh — Build IPS module
set -euo pipefail

cd "$(dirname "$0")/.."
make all
