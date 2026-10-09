#!/bin/sh
# Assemble the active kernel consumers of the SMP APIC interface together.

set -eu

TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$TEST_DIR/../.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM

command -v nasm >/dev/null 2>&1 || {
    echo "FAIL: nasm not found"
    exit 1
}

nasm -f elf64 -Wall -Werror -w-unknown-warning -w-reloc-abs-dword \
    -w-reloc-abs-qword -w-reloc-rel-dword -I "$ROOT_DIR/" \
    "$TEST_DIR/apic_consumers_asm_unit.asm" \
    -o "$TMP_DIR/apic_consumers_asm_unit.o"

test -s "$TMP_DIR/apic_consumers_asm_unit.o" || {
    echo "FAIL: APIC consumer object harness produced no output"
    exit 1
}

echo "PASS: xAPIC/x2APIC memory consumers assemble cleanly"
