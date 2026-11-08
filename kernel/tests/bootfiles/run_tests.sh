#!/bin/sh
# =============================================================================
# kernel/tests/bootfiles/run_tests.sh — the boot files, on the host
# =============================================================================
# Assembles stub.asm (kernel/exec/bootfiles.asm with the UPK verifier and its
# hashes and signatures), links it into a shared object, and runs
# test_bootfiles.py against packages built by boot/mkbootpkg.py. No QEMU.
#
# usage: sh kernel/tests/bootfiles/run_tests.sh   (from anywhere in the repo)
# exit status: 0 if everything passed, 1 otherwise
# =============================================================================
set -eu
export PYTHONDONTWRITEBYTECODE=1

TESTS_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$TESTS_DIR/../../.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT HUP INT TERM

cd "$ROOT"
echo "== assembling kernel/tests/bootfiles/stub.asm"
if ! out=$(nasm -f elf64 -I"$ROOT/" -Werror=number-overflow \
               -o "$WORK/stub.o" kernel/tests/bootfiles/stub.asm 2>&1) || [ -n "$out" ]; then
    echo "FAIL assembly"
    echo "$out" | sed 's/^/    /'
    exit 1
fi
ld -shared -Bsymbolic -z noexecstack -o "$WORK/stub.so" "$WORK/stub.o"

echo "== running tests"
if python3 "$TESTS_DIR/test_bootfiles.py" "$WORK/stub.so"; then
    echo "ALL PASSED"
    exit 0
fi
echo "FAILED"
exit 1
