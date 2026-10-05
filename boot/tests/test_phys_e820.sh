#!/bin/sh
# Assemble and execute the real 64-bit E820 parser against synthetic maps.

set -eu

TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$TEST_DIR/../.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM

command -v nasm >/dev/null 2>&1 || {
    echo "FAIL: nasm not found"
    exit 1
}
command -v ld >/dev/null 2>&1 || {
    echo "FAIL: ld not found"
    exit 1
}

nasm -f elf64 -I "$ROOT_DIR/" \
    "$TEST_DIR/phys_e820_unit.asm" -o "$TMP_DIR/phys_e820_unit.o"
ld -o "$TMP_DIR/phys_e820_unit" "$TMP_DIR/phys_e820_unit.o"

set +e
"$TMP_DIR/phys_e820_unit"
STATUS=$?
set -e

[ "$STATUS" -eq 0 ] || {
    echo "FAIL: physical E820 parser unit case $STATUS"
    exit 1
}

echo "PASS: physical E820 parser bounds, alignment, sparse-map, and overflow contracts"
