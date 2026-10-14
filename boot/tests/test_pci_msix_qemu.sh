#!/bin/sh
# Prove one device-originated MSI-X using QEMU's e1000e endpoint.

set -eu

TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

echo "[test_pci_msix_qemu] Booting OVMF/q35 with one e1000e endpoint..."
UEFI_QEMU_E1000E=1 sh "$TEST_DIR/test_ovmf_qemu.sh"

echo "[test_pci_msix_qemu] Booting four x2APIC CPUs with bridged EDU and e1000e..."
UEFI_QEMU_EDU=1 \
UEFI_QEMU_EDU_BRIDGE=1 \
UEFI_QEMU_E1000E=1 \
UEFI_QEMU_SMP=4 \
UEFI_EXPECT_SMP=4 \
UEFI_QEMU_CPU='max,x2apic=on' \
UEFI_EXPECT_APIC_MODE=x2APIC \
sh "$TEST_DIR/test_ovmf_qemu.sh"

echo "PASS: e1000e delivered one owned MSI-X and retained a live scheduler"
