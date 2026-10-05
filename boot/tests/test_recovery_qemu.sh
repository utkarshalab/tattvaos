#!/bin/sh
# Exercise the complete survive path with a real QEMU NMI after the first
# successful, post-self-test scheduler heartbeat. The guest must reload the ULF
# image through BIOS, rebuild and verify transition state, then reach the same
# post-self-test heartbeat a second time.

set -eu

TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
IMG="$TEST_DIR/../tattva.img"
QEMU64=$(printenv QEMU 2>/dev/null || true)
[ -n "$QEMU64" ] || QEMU64=qemu-system-x86_64
TIMEOUT=$(printenv RECOVERY_TEST_TIMEOUT 2>/dev/null || true)
[ -n "$TIMEOUT" ] || TIMEOUT=90
HIGHMEM=$(printenv RECOVERY_HIGHMEM 2>/dev/null || true)
[ -n "$HIGHMEM" ] || HIGHMEM=0
TMP_DIR=$(mktemp -d)
LOG="$TMP_DIR/uart.log"
QEMU_ERR="$TMP_DIR/qemu.stderr"
QMP_LOG="$TMP_DIR/qmp.log"
QMP_SOCKET="$TMP_DIR/qmp.sock"
QEMU_PID=

show_log() {
    LINES=$(wc -l < "$LOG")
    if [ "$LINES" -le 500 ]; then
        cat "$LOG"
    else
        sed -n '1,300p' "$LOG"
        echo "[test_recovery_qemu] ... $((LINES - 450)) UART lines omitted ..."
        tail -n 150 "$LOG"
    fi
}

cleanup() {
    if [ -n "$QEMU_PID" ] && kill -0 "$QEMU_PID" 2>/dev/null; then
        kill "$QEMU_PID" 2>/dev/null || true
        wait "$QEMU_PID" 2>/dev/null || true
    fi
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT HUP INT TERM

fail() {
    echo "FAIL: $*"
    echo "[test_recovery_qemu] UART output:"
    show_log
    if [ -s "$QEMU_ERR" ]; then
        echo "[test_recovery_qemu] QEMU stderr:"
        cat "$QEMU_ERR"
    fi
    if [ -s "$QMP_LOG" ]; then
        echo "[test_recovery_qemu] QMP transcript:"
        cat "$QMP_LOG"
    fi
    exit 1
}

[ -f "$IMG" ] || fail "image not found: $IMG"
command -v "$QEMU64" >/dev/null 2>&1 || fail "QEMU not found: $QEMU64"
command -v socat >/dev/null 2>&1 || fail "socat is required for QMP control"
command -v timeout >/dev/null 2>&1 || fail "timeout command not found"

: > "$LOG"
: > "$QEMU_ERR"
: > "$QMP_LOG"

if [ "$HIGHMEM" -eq 1 ]; then
    set -- -machine "pc,max-ram-below-4g=256M" -accel tcg
else
    set --
fi

timeout "$TIMEOUT" "$QEMU64" \
    "$@" \
    -drive "format=raw,file=$IMG" \
    -cpu max \
    -m 512 \
    -netdev user,id=n0 \
    -device e1000,netdev=n0 \
    -serial "file:$LOG" \
    -qmp "unix:$QMP_SOCKET,server=on,wait=off" \
    -no-reboot -no-shutdown -display none \
    2>"$QEMU_ERR" &
QEMU_PID=$!

wait_for_count() {
    NEEDLE=$1
    EXPECTED=$2
    LIMIT=$3
    ITER=0
    while [ "$ITER" -lt "$LIMIT" ]; do
        kill -0 "$QEMU_PID" 2>/dev/null || fail "QEMU exited before: $NEEDLE"
        COUNT=$(grep -Fc "$NEEDLE" "$LOG" 2>/dev/null || true)
        if [ "$COUNT" -ge "$EXPECTED" ]; then
            return 0
        fi
        ITER=$((ITER + 1))
        sleep 0.1
    done
    fail "timed out waiting for occurrence $EXPECTED of: $NEEDLE"
}

ITER=0
while [ ! -S "$QMP_SOCKET" ] && [ "$ITER" -lt 100 ]; do
    kill -0 "$QEMU_PID" 2>/dev/null || fail "QEMU exited before opening QMP"
    ITER=$((ITER + 1))
    sleep 0.1
done
[ -S "$QMP_SOCKET" ] || fail "QMP socket was not created"

READY="Tattva Kernel Ready. Entering main execution."
SELFTESTS="Boot memory self-test: PASS"
HEARTBEAT="heartbeat #0"
wait_for_count "$READY" 1 400
wait_for_count "$SELFTESTS" 1 300
wait_for_count "$HEARTBEAT" 1 100

# Negotiate QMP and inject a hardware NMI. Keeping stdin open briefly lets
# socat collect both command replies instead of racing the server greeting.
{
    printf '%s\n' '{"execute":"qmp_capabilities"}'
    printf '%s\n' '{"execute":"inject-nmi"}'
    sleep 0.2
} | socat - "UNIX-CONNECT:$QMP_SOCKET" >"$QMP_LOG" || \
    fail "QMP NMI injection failed"

grep -Fq '"error"' "$QMP_LOG" && fail "QMP rejected the NMI command"

wait_for_count "$READY" 2 600
wait_for_count "$SELFTESTS" 2 300
wait_for_count "$HEARTBEAT" 2 100

if [ "$HIGHMEM" -eq 1 ]; then
    HIGH_E820="base=0x0000000100000000 len=0x0000000010000000 type=1 (usable)"
    grep -Fq "$HIGH_E820" "$LOG" || fail "forced high E820 range was not reported"
    wait_for_count "PMM mapped limit: 4 GiB" 2 1
    wait_for_count "Highmem direct-map R/W: SKIP (RAM above mapped limit is offline)" 2 1
    grep -Fq "Highmem direct-map R/W: PASS phys=" "$LOG" && \
        fail "recovery exposed RAM above the mapped limit"
fi

# Require the recovery story in strict order after the first ready marker.
LAST_LINE=0
for MILESTONE in \
    "$SELFTESTS" \
    "$READY" \
    "$HEARTBEAT" \
    "!!! KERNEL PANIC !!!" \
    "Snapshot checksum valid. Initiating warm recovery..." \
    "Recovery: reloading kernel..." \
    "Recovery long-mode transition verify: OK" \
    "Tattva Kernel Booting..." \
    "$SELFTESTS" \
    "$READY" \
    "$HEARTBEAT"
do
    LINE=$(awk -v after="$LAST_LINE" -v needle="$MILESTONE" \
        'NR > after && index($0, needle) { print NR; exit }' "$LOG")
    [ -n "$LINE" ] || fail "missing or out-of-order recovery milestone: $MILESTONE"
    LAST_LINE=$LINE
done

for FATAL in \
    "Recovery: FAILED" \
    "Recovery long-mode transition verify: FAIL" \
    "Recovery: reloaded ULF" \
    "Recovery: pristine snapshot invalid" \
    "EARLY64 EXCEPTION"
do
    grep -Fq "$FATAL" "$LOG" && fail "fatal recovery diagnostic found: $FATAL"
done

echo "[test_recovery_qemu] UART recovery milestones:"
sed -n '1,220p' "$LOG"
if [ "$HIGHMEM" -eq 1 ]; then
    echo "PASS: high-E820 NMI warm-recovery boot test"
else
    echo "PASS: NMI warm-recovery boot test"
fi
