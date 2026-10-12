#!/bin/sh
# boot/tests/test_highmem_qemu.sh
# Verify sparse identity mapping and allocator publication above 4 GiB.

set -eu

TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
IMG="$TEST_DIR/../tattva.img"
QEMU64=${QEMU:-qemu-system-x86_64}
TIMEOUT=${HIGHMEM_TEST_TIMEOUT:-30}
CPU=${HIGHMEM_QEMU_CPU:-max}
SMP=${HIGHMEM_QEMU_SMP:-1}
MACHINE=${HIGHMEM_QEMU_MACHINE:-pc,max-ram-below-4g=256M}
MEM=${HIGHMEM_QEMU_MEM:-512M}
NUMA=${HIGHMEM_QEMU_NUMA:-none}
HIGH_E820=${HIGHMEM_EXPECT_E820:-base=0x0000000100000000 len=0x0000000010000000 type=1 (usable)}
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

has_exact() {
    awk -v expected="$1" \
        '{ sub(/\r$/, "", $0); if ($0 == expected) found = 1 } END { exit !found }' "$LOG"
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
case "$SMP" in
    ''|*[!0-9]*)
        echo "FAIL: invalid HIGHMEM_QEMU_SMP value: $SMP"
        exit 1
        ;;
esac
[ "$SMP" -ge 1 ] || {
    echo "FAIL: HIGHMEM_QEMU_SMP must be at least 1"
    exit 1
}
case "$NUMA" in
    none)
        set --
        ;;
    default|slit)
        [ "$MEM" = "512M" ] || {
            echo "FAIL: NUMA test topology requires HIGHMEM_QEMU_MEM=512M"
            exit 1
        }
        [ "$SMP" -eq 2 ] || {
            echo "FAIL: NUMA test topology requires HIGHMEM_QEMU_SMP=2"
            exit 1
        }
        set -- \
            -object "memory-backend-ram,size=256M,id=m0" \
            -object "memory-backend-ram,size=256M,id=m1" \
            -numa "node,nodeid=0,cpus=0,memdev=m0" \
            -numa "node,nodeid=1,cpus=1,memdev=m1"
        if [ "$NUMA" = "slit" ]; then
            set -- "$@" \
                -numa "dist,src=0,dst=1,val=20" \
                -numa "dist,src=1,dst=0,val=20"
        fi
        ;;
    *)
        echo "FAIL: invalid HIGHMEM_QEMU_NUMA value: $NUMA"
        exit 1
        ;;
esac

: > "$LOG"
: > "$QEMU_ERR"

echo "[test_highmem_qemu] Booting forced high-E820 configuration..."
set +e
timeout "$TIMEOUT" "$QEMU64" \
    -machine "$MACHINE" \
    -accel tcg \
    -cpu "$CPU" \
    -smp "$SMP" \
    -m "$MEM" \
    -drive "format=raw,file=$IMG,snapshot=on" \
    -netdev user,id=n0 \
    -device e1000,netdev=n0 \
    -serial "file:$LOG" \
    -no-reboot \
    -no-shutdown \
    -display none \
    "$@" \
    2>"$QEMU_ERR"
QEMU_STATUS=$?
set -e

# A healthy guest remains in its kernel loop until timeout terminates it.
# Any earlier exit can be a reset/triple fault with stale success markers.
[ "$QEMU_STATUS" -eq 124 ] || \
    fail "QEMU exited before the test timeout (status $QEMU_STATUS)"

LAST_LINE=0
for MILESTONE in \
    "$HIGH_E820" \
    "PMM mapped limit: 4 GiB" \
    "Paging high map verify: OK" \
    "Highmem direct-map R/W: PASS phys=0x00000001" \
    "Boot memory self-test: PASS" \
    "Tattva Kernel Ready. Entering main execution." \
    "heartbeat #0"
do
    LINE=$(awk -v after="$LAST_LINE" -v needle="$MILESTONE" \
        'NR > after && index($0, needle) { print NR; exit }' "$LOG")
    [ -n "$LINE" ] || fail "missing or out-of-order milestone: $MILESTONE"
    LAST_LINE=$LINE
done

for MILESTONE in \
    "SMP: discovered $SMP processors" \
    "SMP: online $SMP processors" \
    "SMP: released $SMP/$SMP processors"
do
    has_exact "$MILESTONE" || fail "missing exact SMP milestone: $MILESTONE"
done
awk -v periodic="SMP: APIC timer periodic $SMP/$SMP" \
    -v deadline="SMP: APIC timer tsc-deadline $SMP/$SMP" \
    '{ sub(/\r$/, "", $0); if ($0 == periodic || $0 == deadline) found = 1 } END { exit !found }' \
    "$LOG" || fail "missing exact all-core APIC timer milestone"
if [ "$SMP" -gt 1 ]; then
    has_exact "SMP: scheduler park/unpark PASS" || \
        fail "missing multi-core allocator/scheduler lifecycle proof"
else
    has_exact "SMP: scheduler park/unpark SKIP (single CPU)" || \
        fail "missing single-core scheduler lifecycle marker"
fi

case "$NUMA" in
    default)
        has_exact "NUMA: ACPI SRAT table parsing successful." || \
            fail "missing valid SRAT topology milestone"
        has_exact "NUMA: SLIT not found or invalid. Defaulting to SRAT topology distances." || \
            fail "missing safe no-SLIT distance fallback"
        has_exact "NUMA: Node-Local Bitmaps successfully initialized." || \
            fail "missing node-local bitmap publication"
        has_exact "NUMA high-node R/W/free: PASS" || \
            fail "missing node-1 high-memory allocation/free/accounting proof"
        ;;
    slit)
        has_exact "NUMA: ACPI SRAT table parsing successful." || \
            fail "missing valid SRAT topology milestone"
        has_exact "NUMA: ACPI SLIT table parsing successful." || \
            fail "missing valid SLIT topology milestone"
        has_exact "NUMA: Node-Local Bitmaps successfully initialized." || \
            fail "missing node-local bitmap publication"
        has_exact "NUMA high-node R/W/free: PASS" || \
            fail "missing node-1 high-memory allocation/free/accounting proof"
        ;;
esac

grep -Fq "Highmem direct-map R/W: SKIP" "$LOG" && \
    fail "guest left supported high RAM offline"

if grep -Eiq 'EARLY64 EXCEPTION|KERNEL PANIC|(^|[^[:alpha:]])(FAIL|FAILED|FAILURE|ERROR|FATAL|PANIC)([^[:alpha:]]|$)|page fault|triple fault' "$LOG"; then
    fail "fatal diagnostic found in UART output"
fi

echo "PASS: above-4-GiB E820 RAM was mapped, verified, allocated, and released"
