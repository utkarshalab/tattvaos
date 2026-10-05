#!/bin/sh
# Assemble and execute exact-read behavior against a mocked file protocol.

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

nasm -f elf64 -Wall -Werror -w-reloc-rel-dword -w-reloc-abs-qword \
    -I "$ROOT_DIR/" -I "$ROOT_DIR/boot/uefi/" -I "$ROOT_DIR/boot/" \
    "$TEST_DIR/uefi_file_unit.asm" -o "$TMP_DIR/uefi_file_unit.o"
ld -o "$TMP_DIR/uefi_file_unit" "$TMP_DIR/uefi_file_unit.o"

set +e
"$TMP_DIR/uefi_file_unit"
STATUS=$?
set -e

[ "$STATUS" -eq 0 ] || {
    echo "FAIL: UEFI exact-file-read unit case $STATUS"
    exit 1
}

echo "PASS: UEFI exact file reads retry shorts and fail closed on truncation"
