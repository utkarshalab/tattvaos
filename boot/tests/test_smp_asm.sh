#!/bin/sh
# Assemble the complete SMP implementation as an ELF object. This keeps
# mixed-mode trampoline, relocation, and external-linkage regressions cheap to
# diagnose without waiting for the monolithic kernel translation unit.

set -eu

TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$TEST_DIR/../.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM

command -v nasm >/dev/null 2>&1 || {
    echo "FAIL: nasm not found"
    exit 1
}

nasm -f elf64 -Wall -Werror -w-reloc-rel-dword -w-unknown-warning \
    -I "$ROOT_DIR/" \
    "$TEST_DIR/smp_asm_unit.asm" -o "$TMP_DIR/smp_asm_unit.o"

test -s "$TMP_DIR/smp_asm_unit.o" || {
    echo "FAIL: SMP object harness produced no output"
    exit 1
}

assert_acpi_unpublished() {
    START_LABEL=$1
    END_LABEL=$2
    BLOCK=$(awk -v start="$START_LABEL:" -v end="$END_LABEL:" '
        $0 == start { found = 1 }
        found { print }
        found && $0 == end { exit }
    ' "$ROOT_DIR/kernel/arch/x86_64/smp.asm")

    for FIELD in smp_madt_ptr smp_dmar_seen smp_dmar_table \
                 smp_dmar_drhd_count smp_dmar_flags smp_x2apic_veto; do
        printf '%s\n' "$BLOCK" | grep -F "[rel $FIELD], 0" >/dev/null || {
            echo "FAIL: $START_LABEL does not unpublish $FIELD"
            exit 1
        }
    done
}

assert_acpi_unpublished smp_discover .firmware_x2apic
assert_acpi_unpublished .fallback .fatal
assert_acpi_unpublished .fatal_return .done

echo "PASS: SMP discovery, AP-startup, and trampoline source assembles cleanly"
