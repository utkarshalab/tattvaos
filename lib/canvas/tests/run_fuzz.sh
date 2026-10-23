#!/bin/bash
# Fuzz tests: build fuzz_runner.img, run corpus in tests/fuzz/corpus/ on Utkarsha
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
make fuzz
echo "Boot build/img/fuzz_runner.img on Utkarsha with corpus mounted."
