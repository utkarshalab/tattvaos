#!/bin/sh
# Assemble the complete SMP implementation as an ELF object. This keeps
# mixed-mode trampoline, relocation, and external-linkage regressions cheap to
# diagnose without waiting for the monolithic kernel translation unit.

set -eu

TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$TEST_DIR/../.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM

command -v nasm >/dev/null 2>&1 || {
    echo "FAIL: nasm not found"
    exit 1
}

nasm -f elf64 -Wall -Werror -w-reloc-rel-dword -w-unknown-warning \
    -I "$ROOT_DIR/" \
    "$TEST_DIR/smp_asm_unit.asm" -o "$TMP_DIR/smp_asm_unit.o"

test -s "$TMP_DIR/smp_asm_unit.o" || {
    echo "FAIL: SMP object harness produced no output"
    exit 1
}

echo "PASS: SMP discovery, AP-startup, and trampoline source assembles cleanly"
