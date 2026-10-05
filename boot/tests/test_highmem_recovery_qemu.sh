#!/bin/sh
# Reuse the QMP recovery harness with RAM split across the 4 GiB boundary.

set -eu

TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
RECOVERY_HIGHMEM=1
export RECOVERY_HIGHMEM

sh "$TEST_DIR/test_recovery_qemu.sh"
