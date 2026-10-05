#!/bin/sh
# Assemble and execute the real UEFI -> canonical memory-map converter.

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
    "$TEST_DIR/uefi_memmap_unit.asm" -o "$TMP_DIR/uefi_memmap_unit.o"
ld -o "$TMP_DIR/uefi_memmap_unit" "$TMP_DIR/uefi_memmap_unit.o"

set +e
"$TMP_DIR/uefi_memmap_unit"
STATUS=$?
set -e

[ "$STATUS" -eq 0 ] || {
    echo "FAIL: UEFI memory-map normalization unit case $STATUS"
    exit 1
}

echo "PASS: UEFI descriptor normalization, bounds, overlap, and fail-closed contracts"
