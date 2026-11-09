#!/bin/bash
# Fuzz tests on the development machine: the wire and input suite
# (test_fuzz) and the decoders (fuzz_media.py), FUZZ_ROUNDS mutants a seed
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
make fuzz FUZZ_ROUNDS="${FUZZ_ROUNDS:-2000}"
