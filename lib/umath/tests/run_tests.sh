#!/bin/sh
# =============================================================================
# umath - unified math library
# tests/run_tests.sh - host-side build check and numeric test suite
# =============================================================================
# Runs on Linux/WSL with nasm, ld and python3 (no C compiler, no QEMU):
#
#   1. Assembles every umath .asm file on its own, then all of them as one
#      translation unit, with number-overflow and "other" warnings promoted
#      to errors. Those two warning classes hid real bugs before: 64-bit
#      immediates silently truncated to 32 bits, and initialized data in
#      .bss silently dropped.
#   2. Links the single translation unit into a shared object and drives it
#      from Python via ctypes, comparing against Python reference results
#      (see test_*.py).
#   3. Runs those tests twice: with every CPU feature the host has, then with
#      UMATH_CPU_MASK=0 (SSE2 baseline), which sends every SSE4/AVX/BMI fast
#      path through its fallback (cpuid/fallback.asm).
#
# usage: sh lib/umath/tests/run_tests.sh   (from anywhere in the repo)
# exit status: 0 if everything passed, 1 otherwise
# =============================================================================
set -eu
export PYTHONDONTWRITEBYTECODE=1    # keep the source tree free of __pycache__

TESTS_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$TESTS_DIR/../../.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT HUP INT TERM

NASM_FLAGS="-f elf64 -I$ROOT/ -Werror=number-overflow -Werror=other"
failed=0

cd "$ROOT"
modules="bits cpuid dtype math_fn memory reduce scalar stability random"

echo "== assembling each file standalone"
count=0
for f in $(for m in $modules; do ls lib/umath/$m/*.asm; done); do
    count=$((count + 1))
    if ! out=$(nasm $NASM_FLAGS -o /dev/null "$f" 2>&1) || [ -n "$out" ]; then
        echo "FAIL $f"
        echo "$out" | sed 's/^/    /'
        failed=1
    fi
done
echo "   $count files"

echo "== assembling all files as one translation unit"
for f in $(for m in $modules; do ls lib/umath/$m/*.asm; done); do
    echo "%include \"$f\""
done > "$WORK/umath_all.asm"
if ! nasm $NASM_FLAGS -o "$WORK/umath_all.o" "$WORK/umath_all.asm" > "$WORK/nasm.log" 2>&1; then
    echo "FAIL single translation unit"
    sed 's/^/    /' "$WORK/nasm.log"
    exit 1
fi
ld -shared -Bsymbolic -z noexecstack -o "$WORK/umath.so" "$WORK/umath_all.o"

for mode in native baseline; do
    if [ "$mode" = baseline ]; then
        export UMATH_CPU_MASK=0     # SSE2 only: every fast path takes its fallback
    else
        unset UMATH_CPU_MASK
    fi
    for t in "$TESTS_DIR"/test_*.py; do
        echo "== $(basename "$t") ($mode)"
        if ! python3 "$t" "$WORK/umath.so"; then
            failed=1
        fi
    done
done

if [ "$failed" -eq 0 ]; then
    echo "umath: all tests passed"
else
    echo "umath: FAILURES (see above)"
fi
exit "$failed"
