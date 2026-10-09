#!/bin/sh
# Assemble and execute the kernel's real MADT parser against hostile tables.

set -eu

TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$TEST_DIR/../.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM

for TOOL in nasm ld; do
    command -v "$TOOL" >/dev/null 2>&1 || {
        echo "FAIL: $TOOL not found"
        exit 1
    }
done

nasm -f elf64 -Wall -Werror -w-reloc-rel-dword -I "$ROOT_DIR/" \
    "$TEST_DIR/madt_unit.asm" -o "$TMP_DIR/madt_unit.o"
ld -o "$TMP_DIR/madt_unit" "$TMP_DIR/madt_unit.o"

set +e
"$TMP_DIR/madt_unit"
STATUS=$?
set -e

[ "$STATUS" -eq 0 ] || {
    echo "FAIL: MADT parser unit case $STATUS"
    exit 1
}

echo "PASS: MADT topology, bounds, LAPIC, APIC-ID, and NMI-route contracts"
