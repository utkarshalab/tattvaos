#!/bin/sh
# Exercise real two-node SRAT ownership both with and without a SLIT matrix.

set -eu

TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

for MODE in default slit; do
    echo "[test_highmem_numa_qemu] topology mode: $MODE"
    HIGHMEM_QEMU_NUMA="$MODE" \
    HIGHMEM_QEMU_SMP=2 \
    HIGHMEM_TEST_TIMEOUT=${HIGHMEM_NUMA_TEST_TIMEOUT:-35} \
        sh "$TEST_DIR/test_highmem_qemu.sh"
done
