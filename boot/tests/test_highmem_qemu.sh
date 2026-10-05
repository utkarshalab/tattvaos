#!/bin/sh
# boot/tests/test_highmem_qemu.sh
# Verify the Phase-A policy for RAM reported above the 4 GiB mapped aperture.

set -eu

TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
IMG="$TEST_DIR/../tattva.img"
QEMU64=${QEMU:-qemu-system-x86_64}
TIMEOUT=${HIGHMEM_TEST_TIMEOUT:-30}
TMP_DIR=$(mktemp -d)
LOG="$TMP_DIR/uart.log"
QEMU_ERR="$TMP_DIR/qemu.stderr"
trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM

fail() {
    echo "FAIL: $*"
    echo "[test_highmem_qemu] UART output:"
    show_log
    if [ -s "$QEMU_ERR" ]; then
        echo "[test_highmem_qemu] QEMU stderr:"
        cat "$QEMU_ERR"
    fi
    exit 1
}

show_log() {
    LOG_LINES=$(wc -l < "$LOG")
    if [ "$LOG_LINES" -le 400 ]; then
        cat "$LOG"
    else
        sed -n '1,240p' "$LOG"
        echo "[test_highmem_qemu] ... $((LOG_LINES - 340)) UART lines omitted ..."
        tail -n 100 "$LOG"
    fi
}

[ -f "$IMG" ] || {
    echo "FAIL: image not found: $IMG"
    exit 1
}
command -v "$QEMU64" >/dev/null 2>&1 || {
    echo "FAIL: QEMU not found: $QEMU64"
    exit 1
}
command -v timeout >/dev/null 2>&1 || {
    echo "FAIL: timeout command not found"
    exit 1
}

: > "$LOG"
: > "$QEMU_ERR"

echo "[test_highmem_qemu] Booting forced high-E820 configuration..."
set +e
timeout "$TIMEOUT" "$QEMU64" \
    -machine "pc,max-ram-below-4g=256M" \
    -accel tcg \
    -cpu max \
    -m 512M \
    -drive "format=raw,file=$IMG,snapshot=on" \
    -netdev user,id=n0 \
    -device e1000,netdev=n0 \
    -serial "file:$LOG" \
    -no-reboot \
    -no-shutdown \
    -display none \
    2>"$QEMU_ERR"
QEMU_STATUS=$?
set -e

# A healthy guest remains in its kernel loop until timeout terminates it.
# Any earlier exit can be a reset/triple fault with stale success markers.
[ "$QEMU_STATUS" -eq 124 ] || \
    fail "QEMU exited before the test timeout (status $QEMU_STATUS)"

LAST_LINE=0
for MILESTONE in \
    "base=0x0000000100000000 len=0x0000000010000000 type=1 (usable)" \
    "PMM mapped limit: 4 GiB" \
    "Highmem direct-map R/W: SKIP (RAM above mapped limit is offline)" \
    "Boot memory self-test: PASS" \
    "Tattva Kernel Ready. Entering main execution." \
    "heartbeat #0"
do
    LINE=$(awk -v after="$LAST_LINE" -v needle="$MILESTONE" \
        'NR > after && index($0, needle) { print NR; exit }' "$LOG")
    [ -n "$LINE" ] || fail "missing or out-of-order milestone: $MILESTONE"
    LAST_LINE=$LINE
done

# Phase A must never expose an allocator-selected frame above the mapped limit.
if grep -Fq "Highmem direct-map R/W: PASS phys=" "$LOG"; then
    fail "guest accessed RAM that should have remained offline"
fi

if grep -Fq "Paging high map verify: OK" "$LOG"; then
    fail "guest unexpectedly installed a high direct map"
fi

if grep -Eiq 'EARLY64 EXCEPTION|KERNEL PANIC|(^|[^[:alpha:]])(FAIL|FAILED|FAILURE|ERROR|FATAL|PANIC)([^[:alpha:]]|$)|page fault|triple fault' "$LOG"; then
    fail "fatal diagnostic found in UART output"
fi

echo "PASS: above-4-GiB E820 RAM remained safely offline at the 4-GiB mapped limit"
