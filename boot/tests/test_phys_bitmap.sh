#!/bin/sh
# Assemble and execute the real PMM bitmap helpers against guarded buffers.

set -eu

TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$TEST_DIR/../.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM

for TOOL in nasm ld; do
    command -v "$TOOL" >/dev/null 2>&1 || {
        echo "FAIL: required command not found: $TOOL"
        exit 1
    }
done

nasm -f elf64 -I "$ROOT_DIR/" \
    "$TEST_DIR/phys_bitmap_unit.asm" -o "$TMP_DIR/phys_bitmap_unit.o"
ld -o "$TMP_DIR/phys_bitmap_unit" "$TMP_DIR/phys_bitmap_unit.o"

set +e
"$TMP_DIR/phys_bitmap_unit"
STATUS=$?
set -e

[ "$STATUS" -eq 0 ] || {
    echo "FAIL: physical bitmap unit case $STATUS"
    exit 1
}

echo "PASS: physical bitmap qword boundaries, ownership, bounds, and guards"
