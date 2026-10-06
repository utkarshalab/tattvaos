#!/bin/sh
# Validate the TCG2 GUID, packed event layout, and Microsoft-x64 protocol ABI.

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

nasm -f elf64 -Wall -Werror -w-reloc-rel-dword -w-reloc-abs-qword \
    -I "$ROOT_DIR/" -I "$ROOT_DIR/boot/" -I "$ROOT_DIR/boot/uefi/" \
    "$TEST_DIR/uefi_tpm_unit.asm" -o "$TMP_DIR/uefi_tpm_unit.o"
ld -o "$TMP_DIR/uefi_tpm_unit" "$TMP_DIR/uefi_tpm_unit.o"

set +e
"$TMP_DIR/uefi_tpm_unit"
STATUS=$?
set -e

[ "$STATUS" -eq 0 ] || {
    echo "FAIL: UEFI TCG2 protocol unit case $STATUS"
    exit 1
}

echo "PASS: UEFI TCG2 GUID, event layout, arguments, and failures are exact"
