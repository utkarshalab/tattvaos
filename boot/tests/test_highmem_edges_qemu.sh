#!/bin/sh
# Combine four sparse-map edges in one boot: a non-qword bitmap tail, a 4 KiB
# trailing mapping tail, NX-disabled leaf policy, and two-core bring-up.

set -eu

TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
HIGHMEM_QEMU_MEM=524292K
HIGHMEM_QEMU_CPU=max,-nx
HIGHMEM_QEMU_SMP=2
HIGHMEM_TEST_TIMEOUT=${HIGHMEM_EDGE_TEST_TIMEOUT:-45}
HIGHMEM_EXPECT_E820="base=0x0000000100000000 len=0x0000000010002000 type=1 (usable)"
export HIGHMEM_QEMU_MEM HIGHMEM_QEMU_CPU HIGHMEM_QEMU_SMP
export HIGHMEM_TEST_TIMEOUT HIGHMEM_EXPECT_E820

sh "$TEST_DIR/test_highmem_qemu.sh"
