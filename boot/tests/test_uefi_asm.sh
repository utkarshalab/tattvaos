#!/bin/sh
# Syntax-check the complete UEFI translation unit as PE/COFF input.
# This is not yet an OVMF boot-ready claim: loader-owned GDT/page-table setup
# and final PE section hygiene remain separate work.

set -eu

TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
BOOT_DIR=$(CDPATH= cd -- "$TEST_DIR/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM

command -v nasm >/dev/null 2>&1 || {
    echo "FAIL: nasm not found"
    exit 1
}
command -v x86_64-w64-mingw32-ld >/dev/null 2>&1 || {
    echo "FAIL: x86_64-w64-mingw32-ld not found"
    exit 1
}
command -v x86_64-w64-mingw32-objdump >/dev/null 2>&1 || {
    echo "FAIL: x86_64-w64-mingw32-objdump not found"
    exit 1
}

# Lock out the two unsafe placements this phase removes.  The linked PE gate
# below proves syntax/relocations; these checks make the ownership policy
# visible when someone later rewrites the file path.
if grep -Eq '1048576|0x2000000' "$BOOT_DIR/uefi/file.asm" "$BOOT_DIR/uefi/entry.asm" "$BOOT_DIR/uefi/handoff.asm"; then
    echo "FAIL: UEFI loader reintroduced a fixed read cap or initrd address"
    exit 1
fi
grep -Fq 'EFI_ALLOCATE_ADDRESS' "$BOOT_DIR/uefi/file.asm" || {
    echo "FAIL: UEFI kernel is not acquired with AllocateAddress"
    exit 1
}
grep -Fq 'EFI_ALLOCATE_MAX_ADDRESS' "$BOOT_DIR/uefi/file.asm" || {
    echo "FAIL: UEFI initrd is not allocated below the bootstrap aperture"
    exit 1
}

# NASM warns for cross-section PE/COFF relative relocations even though the
# final PE linker owns their resolution. Keep every other warning fatal.
nasm -f win64 -Wall -Werror -w-reloc-rel-dword \
    -I "$BOOT_DIR/uefi/" -I "$BOOT_DIR/" \
    "$BOOT_DIR/uefi/entry.asm" -o "$TMP_DIR/uefi-entry.obj"

x86_64-w64-mingw32-ld -mi386pep -nostdlib --subsystem 10 \
    -e efi_main --dynamicbase --nxcompat \
    --file-alignment 512 --section-alignment 4096 \
    -o "$TMP_DIR/BOOTX64.EFI" "$TMP_DIR/uefi-entry.obj"

test -s "$TMP_DIR/BOOTX64.EFI" || {
    echo "FAIL: linked UEFI PE32+ image is empty"
    exit 1
}

x86_64-w64-mingw32-objdump -p "$TMP_DIR/BOOTX64.EFI" |
    grep -q 'Subsystem.*EFI application' || {
        echo "FAIL: linked image is not an EFI application"
        exit 1
    }

echo "PASS: complete UEFI loader assembles and links as a PE32+ EFI application"
