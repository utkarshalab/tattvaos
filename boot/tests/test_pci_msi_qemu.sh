#!/bin/sh
# Prove one device-originated MSI with QEMU's documented EDU endpoint.

set -eu

TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

echo "[test_pci_msi_qemu] Booting OVMF/q35 with EDU at 00:06.0..."
UEFI_QEMU_EDU=1 sh "$TEST_DIR/test_ovmf_qemu.sh"

echo "PASS: EDU delivered one MSI and retained a live scheduler"
