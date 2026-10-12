#!/bin/sh
# boot/tests/run_all.sh
# Run all boot tests in QEMU automatically
#
# Boots QEMU, captures UART output, compares to expected output.
# Exits 0 on pass, 1 on fail.
# Run before every git commit.

set -eu

TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
BOOT_DIR=$(CDPATH= cd -- "$TEST_DIR/.." && pwd)

echo "=== Tattva Boot Test Suite ==="

# The Makefile's test target has already built the complete image.  These
# checks deliberately validate that exact artifact rather than rebuilding a
# different target behind the caller's back.
sh "$TEST_DIR/test_stage1_size.sh"
sh "$TEST_DIR/test_section_hygiene.sh"
sh "$TEST_DIR/test_image_integrity.sh"
sh "$TEST_DIR/test_phys_e820.sh"
sh "$TEST_DIR/test_phys_bitmap.sh"
sh "$TEST_DIR/test_numa_detect.sh"
sh "$TEST_DIR/test_madt.sh"
sh "$TEST_DIR/test_smp_asm.sh"
sh "$TEST_DIR/test_preempt_asm.sh"
sh "$TEST_DIR/test_apic_consumers_asm.sh"
sh "$TEST_DIR/test_pgtable_lock.sh"
sh "$TEST_DIR/test_uefi_memory.sh"
sh "$TEST_DIR/test_uefi_memmap.sh"
sh "$TEST_DIR/test_uefi_ulf.sh"
sh "$TEST_DIR/test_uefi_file.sh"
sh "$TEST_DIR/test_uefi_tpm.sh"
sh "$TEST_DIR/test_uefi_transition_tables.sh"
sh "$TEST_DIR/test_uefi_asm.sh"
sh "$TEST_DIR/test_ovmf_qemu.sh"
sh "$TEST_DIR/test_smp_qemu.sh"
sh "$TEST_DIR/test_boot_qemu.sh"
sh "$TEST_DIR/test_highmem_qemu.sh"
sh "$TEST_DIR/test_highmem_edges_qemu.sh"
sh "$TEST_DIR/test_highmem_numa_qemu.sh"
sh "$TEST_DIR/test_highmem_fallback_qemu.sh"
sh "$TEST_DIR/test_highmem_ovmf_qemu.sh"
sh "$TEST_DIR/test_recovery_qemu.sh"
sh "$TEST_DIR/test_highmem_recovery_qemu.sh"
sh "$TEST_DIR/test_boot_negative.sh"

echo "=== All tests PASSED ==="
exit 0
