#!/bin/sh
# Reuse the OVMF harness with RAM deliberately split across 4 GiB.

set -eu

TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
UEFI_QEMU_MACHINE="q35,max-ram-below-4g=256M"
UEFI_QEMU_MEM=512
UEFI_EXPECT_HIGHMEM=1
export UEFI_QEMU_MACHINE UEFI_QEMU_MEM UEFI_EXPECT_HIGHMEM

sh "$TEST_DIR/test_ovmf_qemu.sh"
