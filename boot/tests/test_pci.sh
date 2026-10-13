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

nasm -f elf64 -Wall -Werror -w-reloc-rel-dword -w-unknown-warning \
    -I "$ROOT_DIR/" "$TEST_DIR/pci_unit.asm" -o "$TMP_DIR/pci_unit.o"
ld -o "$TMP_DIR/pci_unit" "$TMP_DIR/pci_unit.o"

set +e
"$TMP_DIR/pci_unit"
STATUS=$?
set -e
[ "$STATUS" -eq 0 ] || {
    echo "FAIL: PCI ownership/capability case $STATUS"
    exit 1
}

echo "PASS: PCI config ownership and bounded capability contracts"
