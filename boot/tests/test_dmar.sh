#!/bin/sh
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

for UNIT in dmar_unit dmar_drhd_unit vtd_unit; do
    nasm -f elf64 -Wall -Werror -w-reloc-rel-dword -w-unknown-warning -I "$ROOT_DIR/" \
        "$TEST_DIR/$UNIT.asm" -o "$TMP_DIR/$UNIT.o"
    ld -o "$TMP_DIR/$UNIT" "$TMP_DIR/$UNIT.o"
    set +e
    "$TMP_DIR/$UNIT"
    STATUS=$?
    set -e
    [ "$STATUS" -eq 0 ] || {
        echo "FAIL: $UNIT case $STATUS"
        exit 1
    }
done

echo "PASS: DMAR policy/DRHD ownership and VT-d capability contracts"
