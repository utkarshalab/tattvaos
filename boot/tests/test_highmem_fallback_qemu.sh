#!/bin/sh
# Force the full sparse bitmap metadata to exceed the low placement aperture
# and verify that the allocator deliberately boots low-only instead.

set -eu

TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
IMG="$TEST_DIR/../utkarsha.img"
QEMU64=${QEMU:-qemu-system-x86_64}
TIMEOUT=${HIGHMEM_FALLBACK_TEST_TIMEOUT:-45}
TMP_DIR=$(mktemp -d)
LOG="$TMP_DIR/uart.log"
QEMU_ERR="$TMP_DIR/qemu.stderr"
trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM

fail() {
    echo "FAIL: $*"
    cat "$LOG"
    if [ -s "$QEMU_ERR" ]; then
        cat "$QEMU_ERR"
    fi
    exit 1
}

has_exact() {
    awk -v expected="$1" \
        '{ sub(/\r$/, "", $0); if ($0 == expected) found = 1 } END { exit !found }' "$LOG"
}

[ -f "$IMG" ] || fail "image not found: $IMG"
command -v "$QEMU64" >/dev/null 2>&1 || fail "QEMU not found: $QEMU64"
command -v timeout >/dev/null 2>&1 || fail "timeout command not found"

: > "$LOG"
: > "$QEMU_ERR"

echo "[test_highmem_fallback_qemu] Booting sparse 512-GiB metadata fallback configuration..."
set +e
timeout "$TIMEOUT" "$QEMU64" \
    -object "memory-backend-ram,id=ram,size=512G,reserve=off" \
    -machine "pc,memory-backend=ram,max-ram-below-4g=80M" \
    -accel tcg \
    -cpu max \
    -smp 1 \
    -m 512G \
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

[ "$QEMU_STATUS" -eq 124 ] || \
    fail "QEMU exited before the test timeout (status $QEMU_STATUS)"

for MILESTONE in \
    "  base=0x0000000100000000 len=0x0000007FFB000000 type=1 (usable)" \
    "Initializing MM (Physical Allocator)... Highmem metadata: low-only fallback (candidate bitmap did not fit)" \
    "Paging high map verify: SKIP (no supported RAM above 4 GiB)" \
    "Highmem direct-map R/W: SKIP (no supported RAM above 4 GiB)" \
    "Boot memory self-test: PASS" \
    "Utkarsha Kernel Ready. Entering main execution." \
    "heartbeat #0"
do
    has_exact "$MILESTONE" || fail "missing exact fallback milestone: $MILESTONE"
done

grep -Fq "Paging high map verify: OK" "$LOG" && \
    fail "high mappings were published after metadata fallback"
grep -Fq "Highmem direct-map R/W: PASS" "$LOG" && \
    fail "high RAM was allocated after metadata fallback"
if grep -Eiq 'EARLY64 EXCEPTION|KERNEL PANIC|(^|[^[:alpha:]])(FAIL|FAILED|FAILURE|ERROR|FATAL|PANIC)([^[:alpha:]]|$)|page fault|triple fault' "$LOG"; then
    fail "fatal diagnostic found in UART output"
fi

echo "PASS: oversized sparse metadata fell back to a safe low-only allocator"
