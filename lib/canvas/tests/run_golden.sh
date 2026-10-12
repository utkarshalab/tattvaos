#!/bin/bash
# Golden frame tests: build golden_test.img, run on Tattva, compare checksums
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
make test
echo "Boot build/img/golden_test.img on Tattva; mismatch dumps the frame."
