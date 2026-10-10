#!/bin/sh
# Exercise the real UEFI-owned AP trampoline at small and wider SMP counts.
# The underlying OVMF test retains all normal boot/order/fatal assertions.

set -eu

TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
COUNTS=${SMP_TEST_COUNTS:-"2 8"}
X2APIC_CPU=${SMP_X2APIC_CPU:-"max,x2apic=on"}
XAPIC_CPU=${SMP_XAPIC_CPU:-"max,x2apic=off"}

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
    UEFI_QEMU_CPU="$X2APIC_CPU" UEFI_QEMU_SMP="$COUNT" \
        UEFI_EXPECT_SMP="$COUNT" UEFI_EXPECT_APIC_MODE=x2APIC \
        sh "$TEST_DIR/test_ovmf_qemu.sh"
    echo "[test_smp_qemu] Booting BIOS topology with $COUNT processors..."
    BOOT_QEMU_CPU="$X2APIC_CPU" BOOT_QEMU_SMP="$COUNT" \
        BOOT_EXPECT_SMP="$COUNT" BOOT_EXPECT_APIC_MODE=x2APIC \
        sh "$TEST_DIR/test_boot_qemu.sh"
done

echo "[test_smp_qemu] Booting BIOS xAPIC fallback with 2 processors..."
BOOT_QEMU_CPU="$XAPIC_CPU" BOOT_QEMU_SMP=2 BOOT_EXPECT_SMP=2 \
    BOOT_EXPECT_APIC_MODE=xAPIC sh "$TEST_DIR/test_boot_qemu.sh"

echo "PASS: x2APIC UEFI/BIOS matrix ($COUNTS processors) and xAPIC fallback"
