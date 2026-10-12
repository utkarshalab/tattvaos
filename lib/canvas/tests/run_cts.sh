#!/bin/bash
# Conformance suite: build cts_runner.img, require failed=0 for release
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
make cts
echo "Boot build/img/cts_runner.img on Tattva; all suites must pass."
