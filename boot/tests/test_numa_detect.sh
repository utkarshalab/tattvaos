#!/bin/sh
# Assemble and execute the real ACPI/NUMA detector against hostile tables.

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

nasm -f elf64 -I "$ROOT_DIR/" \
    "$TEST_DIR/numa_detect_unit.asm" -o "$TMP_DIR/numa_detect_unit.o"
ld -o "$TMP_DIR/numa_detect_unit" "$TMP_DIR/numa_detect_unit.o"

set +e
"$TMP_DIR/numa_detect_unit"
STATUS=$?
set -e

[ "$STATUS" -eq 0 ] || {
    echo "FAIL: ACPI/NUMA detector unit case $STATUS"
    exit 1
}

echo "PASS: ACPI/NUMA pointer, checksum, length, ownership, and SLIT bounds contracts"
