#!/bin/sh
# Prove one device-originated MSI-X using QEMU's e1000e endpoint.

set -eu

TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

echo "[test_pci_msix_qemu] Booting OVMF/q35 with one e1000e endpoint..."
UEFI_QEMU_E1000E=1 sh "$TEST_DIR/test_ovmf_qemu.sh"

echo "PASS: e1000e delivered one owned MSI-X and retained a live scheduler"
