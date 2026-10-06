#!/bin/sh
# Syntax-check the complete UEFI translation unit as PE/COFF input.
# The runtime OVMF gate is separate; this locks the PE and owned-transition
# structure without requiring a virtual machine.

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
command -v x86_64-w64-mingw32-nm >/dev/null 2>&1 || {
    echo "FAIL: x86_64-w64-mingw32-nm not found"
    exit 1
}

# Lock out the two unsafe placements this phase removes.  The linked PE gate
# below proves syntax/relocations; these checks make the ownership policy
# visible when someone later rewrites the file path.
if grep -Eq '1048576|0x2000000' "$BOOT_DIR/uefi/file.asm" "$BOOT_DIR/uefi/entry.asm" "$BOOT_DIR/uefi/handoff.asm"; then
    echo "FAIL: UEFI loader reintroduced a fixed read cap or initrd address"
    exit 1
fi
grep -Fq 'EFI_ALLOCATE_MAX_ADDRESS' "$BOOT_DIR/uefi/file.asm" || {
    echo "FAIL: UEFI payloads are not allocated below the bootstrap aperture"
    exit 1
}
grep -Fq 'uefi_transition_prepare' "$BOOT_DIR/uefi/entry.asm" || {
    echo "FAIL: UEFI entry does not prepare loader-owned CPU state"
    exit 1
}
grep -Fq 'uefi_transition_verify_ready' "$BOOT_DIR/uefi/handoff.asm" || {
    echo "FAIL: UEFI handoff does not reverify transition state"
    exit 1
}
grep -Fq 'uefi_memory_map_acquire' "$BOOT_DIR/uefi/entry.asm" || {
    echo "FAIL: UEFI entry does not acquire a sized firmware-owned memory map"
    exit 1
}
if grep -Eq 'uefi_mem_map_buf:.*resb' "$BOOT_DIR/uefi/entry.asm" "$BOOT_DIR/uefi/memory.asm"; then
    echo "FAIL: UEFI loader reintroduced a fixed static memory-map buffer"
    exit 1
fi

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

PE_HEADERS="$TMP_DIR/pe-headers.txt"
PE_SECTIONS="$TMP_DIR/pe-sections.txt"
PE_SYMBOLS="$TMP_DIR/pe-symbols.txt"
x86_64-w64-mingw32-objdump -p "$TMP_DIR/BOOTX64.EFI" > "$PE_HEADERS"
x86_64-w64-mingw32-objdump -h "$TMP_DIR/BOOTX64.EFI" > "$PE_SECTIONS"
x86_64-w64-mingw32-nm -n "$TMP_DIR/BOOTX64.EFI" > "$PE_SYMBOLS"

grep -q 'Subsystem.*EFI application' "$PE_HEADERS" || {
        echo "FAIL: linked image is not an EFI application"
        exit 1
    }
for FLAG in DYNAMIC_BASE NX_COMPAT; do
    grep -q "$FLAG" "$PE_HEADERS" || {
        echo "FAIL: linked image is missing PE protection flag: $FLAG"
        exit 1
    }
done

# Lock the W^X ownership that OVMF itself enforces: code is RX, mutable state is
# data, and immutable GUIDs are read-only data.
awk '
    $2 == ".text" {
        getline
        if (index($0, "READONLY") && index($0, "CODE") &&
            !index($0, "DATA")) text_ok = 1
    }
    $2 == ".data" {
        getline
        if (!index($0, "READONLY") && !index($0, "CODE") &&
            index($0, "DATA")) data_ok = 1
    }
    $2 == ".rdata" {
        getline
        if (index($0, "READONLY") && !index($0, "CODE") &&
            index($0, "DATA")) rdata_ok = 1
    }
    END { exit !(text_ok && data_ok && rdata_ok) }
' "$PE_SECTIONS" || {
    echo "FAIL: PE code/data sections do not enforce the expected W^X policy"
    exit 1
}

for SYMBOL in tcg2_protocol tcg2_event uefi_transition_stub_page_addr \
              uefi_mem_map_buf uefi_mem_map_capacity; do
    grep -Eq "[[:space:]][dD][[:space:]]+$SYMBOL$" "$PE_SYMBOLS" || {
        echo "FAIL: mutable UEFI symbol is not in writable data: $SYMBOL"
        exit 1
    }
done
grep -Eq '[[:space:]][rR][[:space:]]+efi_tcg2_protocol_guid$' "$PE_SYMBOLS" || {
    echo "FAIL: TCG2 protocol GUID is not in read-only data"
    exit 1
}
grep -Eq '[[:space:]][tT][[:space:]]+uefi_transition_stub_page$' "$PE_SYMBOLS" || {
    echo "FAIL: transition stub is not in executable code"
    exit 1
}

STUB=$(awk '$3 == "uefi_transition_stub_page" { print $1; exit }' "$PE_SYMBOLS")
STUB_END=$(awk '$3 == "uefi_transition_stub_end" { print $1; exit }' "$PE_SYMBOLS")
[ -n "$STUB" ] && [ -n "$STUB_END" ] || {
    echo "FAIL: transition stub boundary symbols are missing"
    exit 1
}
case "$STUB" in
    *000) ;;
    *)
        echo "FAIL: transition stub does not begin on a PE page boundary"
        exit 1
        ;;
esac
[ "${STUB%???}" = "${STUB_END%???}" ] || {
    echo "FAIL: transition stub crosses its isolated PE page"
    exit 1
}

PE_ENTRY=$(x86_64-w64-mingw32-objdump -f "$TMP_DIR/BOOTX64.EFI" |
    awk '/start address/ { value=$NF; sub(/^0x/, "", value); print value; exit }')
EFI_MAIN=$(awk '$3 == "efi_main" { print $1; exit }' "$PE_SYMBOLS")
[ "$PE_ENTRY" = "$EFI_MAIN" ] || {
    echo "FAIL: PE entry point is not efi_main"
    exit 1
}

echo "PASS: UEFI PE32+ entry, W^X sections, ownership, and stub isolation are exact"
