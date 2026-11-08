#!/bin/sh
# =============================================================================
# lib/ubt - tests/run_tests.sh - host build check and test suite
# =============================================================================
# Runs on the development machine with nasm, ld and python3 (no QEMU):
#
#   1. Assembles lib/ubt/ubt.asm (with lib/usb and lib/input) as one unit, with
#      number-overflow and "other" warnings promoted to errors.
#   2. Links it into a shared object and drives it from Python (ctypes):
#      every tests/test_*.py gets the library's path, except
#      test_bt_kernel.py: tests/bkstub.asm, the Bluetooth and USB kernel
#      glue with PCI, mapping and the console stubbed.
#
# usage: sh lib/ubt/tests/run_tests.sh   (from anywhere in the repo)
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
    if ! out=$(nasm -f elf64 -I"$ROOT/" -Werror=number-overflow -Werror=other \
                   -o "$WORK/$2.o" "$1" 2>&1) || [ -n "$out" ]; then
        echo "FAIL assembly"
        echo "$out" | sed 's/^/    /'
        exit 1
    fi
    ld -shared -Bsymbolic -z noexecstack -o "$WORK/$2.so" "$WORK/$2.o"
}
build lib/ubt/ubt.asm ubt
build lib/ubt/tests/bkstub.asm bkstub

echo "== running tests"
failed=0
for t in "$TESTS_DIR"/test_*.py; do
    so="$WORK/ubt.so"
    case "$(basename "$t")" in test_bt_kernel.py) so="$WORK/bkstub.so" ;; esac
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
