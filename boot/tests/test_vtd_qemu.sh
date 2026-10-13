#!/bin/sh
# Prove that the retained QEMU DMAR unit is safely readable and advertises
# interrupt-remapping support. The kernel still performs no VT-d writes.

set -eu

TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

echo "[test_vtd_qemu] Booting OVMF/q35 with interrupt remapping exposed..."
UEFI_QEMU_MACHINE=q35 \
UEFI_QEMU_CPU="${VTD_QEMU_CPU:-max,x2apic=on}" \
UEFI_QEMU_IOMMU=1 \
UEFI_EXPECT_APIC_MODE=x2APIC \
UEFI_EXPECT_VTD_UNITS=1 \
sh "$TEST_DIR/test_ovmf_qemu.sh"

echo "PASS: OVMF exposed one read-only validated VT-d remapping unit"
