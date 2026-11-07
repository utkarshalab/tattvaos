#!/bin/sh
# =============================================================================
# lib/input - tests/run_tests.sh - host build check and test suite
# =============================================================================
# Runs on the development machine with nasm, ld and python3 (no QEMU):
#
#   1. Assembles lib/input/input.asm as one translation unit with
#      number-overflow and "other" warnings promoted to errors.
#   2. Links it into a shared object and drives it from Python (ctypes),
#      with port I/O replaced by a simulated PS/2 controller and keyboard
#      (sim_ps2.py).
#
# tests/tp_stub.asm builds the touchpad's kernel glue (kernel_touchpad.asm)
# with GPIO, I2C, the ACPI interpreter and stubbed kernel symbols, for
# test_touchpad_kernel.py. lib/input/kernel.asm needs the scheduler, so it
# is checked by the kernel build (boot/Makefile), not here.
#
# usage: sh lib/input/tests/run_tests.sh   (from anywhere in the repo)
# exit status: 0 if everything passed, 1 otherwise
# =============================================================================
set -eu
export PYTHONDONTWRITEBYTECODE=1

TESTS_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$TESTS_DIR/../../.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT HUP INT TERM

cd "$ROOT"
build() {   # source, name
    echo "== assembling $1"
    if ! out=$(nasm -f elf64 -I"$ROOT/" -Werror=number-overflow -Werror=other                    -o "$WORK/$2.o" "$1" 2>&1) || [ -n "$out" ]; then
        echo "FAIL assembly"
        echo "$out" | sed 's/^/    /'
        exit 1
    fi
    ld -shared -Bsymbolic -z noexecstack -o "$WORK/$2.so" "$WORK/$2.o"
}
build lib/input/input.asm input
build lib/input/tests/tp_stub.asm tp

echo "== running tests"
failed=0
for t in "$TESTS_DIR"/test_*.py; do
    so="$WORK/input.so"
    case "$(basename "$t")" in test_touchpad_kernel.py|test_acpi_input.py) so="$WORK/tp.so" ;; esac
    if ! python3 "$t" "$so"; then
        failed=1
    fi
done

if [ $failed -eq 0 ]; then
    echo "ALL PASSED"
else
    echo "FAILED"
fi
exit $failed
