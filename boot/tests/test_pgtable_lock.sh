#!/bin/sh
# Execute the non-TSX page-table lock path and verify adjacent bytes survive.

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

nasm -f elf64 -Wall -Werror -w-unknown-warning -w-reloc-rel-dword -I "$ROOT_DIR/" "$TEST_DIR/pgtable_lock_unit.asm" -o "$TMP_DIR/pgtable_lock_unit.o"
ld -nostdlib -static -o "$TMP_DIR/pgtable_lock_unit" "$TMP_DIR/pgtable_lock_unit.o"

"$TMP_DIR/pgtable_lock_unit"
echo "PASS: traditional page-table lock targets only its selected byte"
