#!/bin/sh
# =============================================================================
# lib/io/acpi/aml - tests/run_tests.sh - host build check and test suite
# =============================================================================
# Runs on the development machine with nasm, ld and python3 (no QEMU):
#
#   1. Assembles lib/io/acpi/aml/aml.asm as one translation unit, and
#      tests/kstub.asm (the kernel glue, kernel.asm, with the kernel symbols
#      it uses stubbed), with number-overflow and "other" warnings promoted
#      to errors.
#   2. Links each into a shared object and drives them from Python (ctypes)
#      with tables built by aml_gen.py: test_kernel.py gets the kernel glue,
#      every other test_*.py the interpreter alone.
#
# usage: sh lib/io/acpi/aml/tests/run_tests.sh   (from anywhere in the repo)
# exit status: 0 if everything passed, 1 otherwise
# =============================================================================
set -eu
export PYTHONDONTWRITEBYTECODE=1

TESTS_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$TESTS_DIR/../../../../.." && pwd)
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
build lib/io/acpi/aml/aml.asm aml
build lib/io/acpi/aml/tests/kstub.asm kstub

echo "== running tests"
failed=0
for t in "$TESTS_DIR"/test_*.py; do
    so="$WORK/aml.so"
    case "$(basename "$t")" in test_kernel.py|test_events.py|test_power.py) so="$WORK/kstub.so" ;; esac
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
