#!/bin/sh
# Exercise the real UEFI-owned AP trampoline at small and wider SMP counts.
# The underlying OVMF test retains all normal boot/order/fatal assertions.

set -eu

TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
COUNTS=${SMP_TEST_COUNTS:-"2 8"}

set -- $COUNTS
[ "$#" -gt 0 ] || {
    echo "FAIL: SMP_TEST_COUNTS contains no processor counts"
    exit 1
}

for COUNT in "$@"; do
    case "$COUNT" in
        ''|*[!0-9]*)
            echo "FAIL: invalid SMP test count: $COUNT"
            exit 1
            ;;
    esac
    [ "$COUNT" -ge 2 ] || {
        echo "FAIL: SMP test count must be at least 2: $COUNT"
        exit 1
    }

    echo "[test_smp_qemu] Booting UEFI topology with $COUNT processors..."
    UEFI_QEMU_SMP="$COUNT" UEFI_EXPECT_SMP="$COUNT" \
        sh "$TEST_DIR/test_ovmf_qemu.sh"
    echo "[test_smp_qemu] Booting BIOS topology with $COUNT processors..."
    BOOT_QEMU_SMP="$COUNT" BOOT_EXPECT_SMP="$COUNT" \
        sh "$TEST_DIR/test_boot_qemu.sh"
done

echo "PASS: UEFI and BIOS AP startup/rendezvous matrix ($COUNTS processors)"
