#!/bin/sh
# =============================================================================
# lib/io/gpio - tests/run_tests.sh - host build check and test suite
# =============================================================================
# Runs on the development machine with nasm, ld and python3 (no QEMU):
#
#   1. Assembles lib/io/gpio/gpio.asm as one translation unit with
#      number-overflow and "other" warnings promoted to errors.
#   2. Links it into a shared object and drives it from Python (ctypes),
#      with register access replaced by a simulated AMD GPIO controller
#      (sim_amd.py).
#
# usage: sh lib/io/gpio/tests/run_tests.sh   (from anywhere in the repo)
# exit status: 0 if everything passed, 1 otherwise
# =============================================================================
set -eu
export PYTHONDONTWRITEBYTECODE=1

TESTS_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$TESTS_DIR/../../../.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT HUP INT TERM

cd "$ROOT"
echo "== assembling lib/io/gpio/gpio.asm"
if ! out=$(nasm -f elf64 -I"$ROOT/" -Werror=number-overflow -Werror=other \
               -o "$WORK/gpio.o" lib/io/gpio/gpio.asm 2>&1) || [ -n "$out" ]; then
    echo "FAIL assembly"
    echo "$out" | sed 's/^/    /'
    exit 1
fi
ld -shared -Bsymbolic -z noexecstack -o "$WORK/gpio.so" "$WORK/gpio.o"

echo "== running tests"
failed=0
for t in "$TESTS_DIR"/test_*.py; do
    if ! python3 "$t" "$WORK/gpio.so"; then
        failed=1
    fi
done

if [ $failed -eq 0 ]; then
    echo "ALL PASSED"
else
    echo "FAILED"
fi
exit $failed
