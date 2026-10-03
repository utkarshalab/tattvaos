#!/bin/sh
# boot/tests/test_boot_qemu.sh
# Boot Tattva OS in QEMU and verify UART output
#
set -eu

TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
IMG="$TEST_DIR/../tattva.img"
QEMU64=${QEMU:-qemu-system-x86_64}
TIMEOUT=${BOOT_TEST_TIMEOUT:-30}
TMP_DIR=$(mktemp -d)
LOG="$TMP_DIR/uart.log"
QEMU_ERR="$TMP_DIR/qemu.stderr"
trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM

if ! command -v "$QEMU64" >/dev/null 2>&1; then
    echo "FAIL: QEMU not found: $QEMU64"
    exit 1
fi

if ! command -v timeout >/dev/null 2>&1; then
    echo "FAIL: timeout command not found"
    exit 1
fi

if [ ! -f "$IMG" ]; then
    echo "FAIL: image not found: $IMG"
    exit 1
fi

echo "[test_boot_qemu] Booting in QEMU..."

: > "$LOG"
: > "$QEMU_ERR"
set +e
timeout "$TIMEOUT" "$QEMU64" \
    -drive "format=raw,file=$IMG" \
    -cpu max \
    -m 512 \
    -netdev user,id=n0 \
    -device e1000,netdev=n0 \
    -serial "file:$LOG" \
    -no-reboot \
    -no-shutdown \
    -display none \
    2>"$QEMU_ERR"
QEMU_STATUS=$?
set -e

echo "[test_boot_qemu] UART output:"
LOG_LINES=$(wc -l < "$LOG")
if [ "$LOG_LINES" -le 400 ]; then
    cat "$LOG"
else
    # A recurring exception can otherwise dump megabytes into CI output and
    # hide the first useful frame.  Preserve both the first fault and tail.
    sed -n '1,240p' "$LOG"
    echo "[test_boot_qemu] ... $((LOG_LINES - 340)) UART lines omitted ..."
    tail -n 100 "$LOG"
fi

# A healthy guest remains in its kernel loop until the harness timeout stops
# QEMU.  Any earlier QEMU exit (including a reset caused by a triple fault) is
# a failure even if the partial UART log happened to contain old milestones.
if [ "$QEMU_STATUS" -ne 124 ]; then
    echo "FAIL: QEMU exited before the test timeout (status $QEMU_STATUS)"
    if [ -s "$QEMU_ERR" ]; then
        echo "[test_boot_qemu] QEMU stderr:"
        cat "$QEMU_ERR"
    fi
    exit 1
fi

PASS=1

# Every milestone must occur after its predecessor.  Presence-only checks can
# incorrectly accept duplicated or stale diagnostics after a failed transition.
LAST_LINE=0
for MILESTONE in \
    "Tattva OS  |  Stage2 OK" \
    "A20...    OK" \
    "CPU...    OK" \
    "GDT verify: OK" \
    "Paging verify: OK" \
    "IDT64 verify: OK" \
    "Long-mode transition verify: OK" \
    "Long mode OK" \
    "Tattva Kernel Booting..." \
    "BootInfo Pointer: 0x0000000000007000" \
    "GS Accessor Test (CPU/Stack): 0/" \
    "Tattva Kernel Ready. Entering main execution."
do
    LINE=$(awk -v after="$LAST_LINE" -v needle="$MILESTONE" \
        'NR > after && index($0, needle) { print NR; exit }' "$LOG")
    if [ -z "$LINE" ]; then
        echo "FAIL: missing or out-of-order boot milestone: $MILESTONE"
        PASS=0
    else
        LAST_LINE=$LINE
    fi
done

if ! grep -Eq 'base=0x[0-9A-F]{16} len=0x[0-9A-F]{16} type=[0-9]+' "$LOG"; then
    echo "FAIL: E820 entries are not rendered as fixed-width 64-bit values"
    PASS=0
fi

if grep -Eq 'base=0x[0-9A-F]{8}0x|len=0x[0-9A-F]{8}0x' "$LOG"; then
    echo "FAIL: E820 output contains a duplicated hexadecimal prefix"
    PASS=0
fi

if ! grep -Eq 'VBE\.\.\.[[:space:]]+(OK [0-9]+x[0-9]+x(16|24|32)|SKIP \(text mode\))' "$LOG"; then
    echo "FAIL: VBE did not report a valid mode or explicit text fallback"
    PASS=0
fi

for FATAL in \
    "EARLY64 EXCEPTION" \
    "GDT verify: FAIL" \
    "Paging verify: FAIL" \
    "IDT64 verify: FAIL" \
    "Long-mode transition verify: FAIL"
do
    if grep -Fq "$FATAL" "$LOG"; then
        echo "FAIL: fatal transition diagnostic found: $FATAL"
        PASS=0
    fi
done

if grep -Eiq '(^|[^[:alpha:]])(FAIL|ERROR|FATAL|PANIC)([^[:alpha:]]|$)|page fault|triple fault' "$LOG"; then
    echo "FAIL: fatal diagnostic found in UART output"
    PASS=0
fi

if [ $PASS -eq 1 ]; then
    echo "PASS: boot test"
    exit 0
else
    exit 1
fi
