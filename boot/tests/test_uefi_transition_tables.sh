#!/bin/sh
# Assemble and execute the real UEFI transition page-table builder/verifier.

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

nasm -f elf64 -Wall -Werror -w-reloc-rel-dword \
    -I "$ROOT_DIR/" -I "$ROOT_DIR/boot/" -I "$ROOT_DIR/boot/uefi/" \
    "$TEST_DIR/uefi_transition_tables_unit.asm" \
    -o "$TMP_DIR/uefi_transition_tables_unit.o"
ld -Ttext=0x10000000 -o "$TMP_DIR/uefi_transition_tables_unit" \
    "$TMP_DIR/uefi_transition_tables_unit.o"

set +e
"$TMP_DIR/uefi_transition_tables_unit"
STATUS=$?
set -e

[ "$STATUS" -eq 0 ] || {
    echo "FAIL: UEFI transition-table unit case $STATUS"
    exit 1
}

echo "PASS: UEFI transition tables are exact, W^X, bounded, and fail closed"
