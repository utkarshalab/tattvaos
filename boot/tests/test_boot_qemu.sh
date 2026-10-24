#!/bin/sh
# boot/tests/test_boot_qemu.sh
# Boot Utkarsha OS in QEMU and verify UART output
#
set -eu

TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
IMG="$TEST_DIR/../utkarsha.img"
QEMU64=${QEMU:-qemu-system-x86_64}
TIMEOUT=${BOOT_TEST_TIMEOUT:-30}
CPU=${BOOT_QEMU_CPU:-max}
SMP=${BOOT_QEMU_SMP:-1}
EXPECT_SMP=${BOOT_EXPECT_SMP:-}
EXPECT_APIC_MODE=${BOOT_EXPECT_APIC_MODE:-}
TMP_DIR=$(mktemp -d)
LOG="$TMP_DIR/uart.log"
QEMU_ERR="$TMP_DIR/qemu.stderr"
trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM

case "$SMP" in
    ''|*[!0-9]*)
        echo "FAIL: invalid BOOT_QEMU_SMP value: $SMP"
        exit 1
        ;;
esac
[ "$SMP" -ge 1 ] || {
    echo "FAIL: BOOT_QEMU_SMP must be at least 1"
    exit 1
}
case "$EXPECT_SMP" in
    ''|*[!0-9]*) [ -z "$EXPECT_SMP" ] || {
        echo "FAIL: invalid BOOT_EXPECT_SMP value: $EXPECT_SMP"
        exit 1
    } ;;
esac
case "$EXPECT_APIC_MODE" in
    ''|xAPIC|x2APIC) ;;
    *)
        echo "FAIL: invalid BOOT_EXPECT_APIC_MODE value: $EXPECT_APIC_MODE"
        exit 1
        ;;
esac

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
    -cpu "$CPU" \
    -smp "$SMP" \
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
    "Utkarsha OS  |  Stage2 OK" \
    "A20...    OK" \
    "CPU...    OK" \
    "GDT verify: OK" \
    "Paging verify: OK" \
    "IDT64 verify: OK" \
    "Long-mode transition verify: OK" \
    "Long mode OK" \
    "Utkarsha Kernel Booting..." \
    "BootInfo Pointer: 0x0000000000007000" \
    "GS Accessor Test (CPU/Stack): 0/" \
    "Boot memory self-test: PASS" \
    "UBF app: hello from a loaded program" \
    "UBF app: imports, relocations and data work" \
    "UBF loader: hello.ubf loaded, ran and returned 42: PASS" \
    "UBF loader: tampered image refused: PASS" \
    "Utkarsha Kernel Ready. Entering main execution." \
    "heartbeat #0"
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

for MILESTONE in \
    "Paging high map verify: SKIP (no supported RAM above 4 GiB)" \
    "Highmem direct-map R/W: SKIP (no supported RAM above 4 GiB)"
do
    grep -Fq "$MILESTONE" "$LOG" || {
        echo "FAIL: missing no-high-memory milestone: $MILESTONE"
        PASS=0
    }
done
if grep -Fq "Paging high map verify: OK" "$LOG" || \
   grep -Fq "Highmem direct-map R/W: PASS" "$LOG"; then
    echo "FAIL: ordinary low-memory BIOS boot unexpectedly published high RAM"
    PASS=0
fi

if ! grep -Eq 'VBE\.\.\.[[:space:]]+(OK [0-9]+x[0-9]+x(16|24|32)|SKIP \(text mode\))' "$LOG"; then
    echo "FAIL: VBE did not report a valid mode or explicit text fallback"
    PASS=0
fi

if [ -n "$EXPECT_SMP" ]; then
    SMP_LAST_LINE=0
    for SMP_MILESTONE in \
        "SMP: discovered $EXPECT_SMP processors" \
        "SMP: rendezvous $EXPECT_SMP/$EXPECT_SMP" \
        "SMP: online $EXPECT_SMP processors" \
        "SMP: released $EXPECT_SMP/$EXPECT_SMP processors"
    do
        SMP_LINE=$(awk -v after="$SMP_LAST_LINE" -v needle="$SMP_MILESTONE" \
            'NR > after { sub(/\r$/, "", $0); if ($0 == needle) { print NR; exit } }' "$LOG")
        if [ -z "$SMP_LINE" ]; then
            echo "FAIL: missing, inexact, or out-of-order SMP milestone: $SMP_MILESTONE"
            PASS=0
        else
            SMP_LAST_LINE=$SMP_LINE
        fi
    done
    if grep -Eq 'SMP: (disabled by validation code|AP startup failed)' "$LOG"; then
        echo "FAIL: BIOS SMP boot fell back to BSP-only mode"
        PASS=0
    fi
fi

if [ -n "$EXPECT_APIC_MODE" ]; then
    if ! awk -v expected="SMP: APIC mode $EXPECT_APIC_MODE" \
        '{ sub(/\r$/, "", $0); if ($0 == expected) found = 1 } END { exit !found }' "$LOG"; then
        echo "FAIL: missing exact APIC-mode marker: SMP: APIC mode $EXPECT_APIC_MODE"
        PASS=0
    fi
fi

TIMER_CPUS=$SMP
[ -z "$EXPECT_SMP" ] || TIMER_CPUS=$EXPECT_SMP
TIMER_LINE=$(awk -v periodic="SMP: APIC timer periodic $TIMER_CPUS/$TIMER_CPUS" \
    -v deadline="SMP: APIC timer tsc-deadline $TIMER_CPUS/$TIMER_CPUS" \
    '{ sub(/\r$/, "", $0); if ($0 == periodic || $0 == deadline) { print NR; exit } }' "$LOG")
if [ -z "$TIMER_LINE" ]; then
    echo "FAIL: missing exact all-core APIC timer marker for $TIMER_CPUS processors"
    PASS=0
fi

IOAPIC_LINE=
if [ -n "$TIMER_LINE" ]; then
    IOAPIC_LINE=$(awk -v after="$TIMER_LINE" -v expected="IOAPIC: PIT IRQ0 delivery PASS" \
        -v heartbeat="heartbeat #0" \
        'NR > after { sub(/\r$/, "", $0); if ($0 == heartbeat) exit; if ($0 == expected) { print NR; exit } }' "$LOG")
fi
if [ -z "$IOAPIC_LINE" ]; then
    echo "FAIL: missing exact IOAPIC/PIT delivery proof after the local timer proof"
    PASS=0
fi

if [ "$TIMER_CPUS" -gt 1 ]; then
    LIFECYCLE_MARKER="SMP: scheduler park/unpark PASS"
else
    LIFECYCLE_MARKER="SMP: scheduler park/unpark SKIP (single CPU)"
fi
LIFECYCLE_LINE=
if [ -n "$IOAPIC_LINE" ]; then
    LIFECYCLE_LINE=$(awk -v after="$IOAPIC_LINE" -v expected="$LIFECYCLE_MARKER" \
        -v heartbeat="heartbeat #0" \
        'NR > after { sub(/\r$/, "", $0); if ($0 == heartbeat) exit; if ($0 == expected) { print NR; exit } }' "$LOG")
fi
if [ -z "$LIFECYCLE_LINE" ]; then
    echo "FAIL: missing exact scheduler lifecycle marker between IOAPIC proof and first heartbeat: $LIFECYCLE_MARKER"
    PASS=0
fi

if [ "$TIMER_CPUS" -gt 1 ]; then
    DRAIN_MARKER="SMP: scheduler queue drain PASS"
    TARGET_MARKER="SMP: scheduler target/affinity/wake PASS"
else
    DRAIN_MARKER="SMP: scheduler queue drain SKIP (single CPU)"
    TARGET_MARKER="SMP: scheduler target/affinity/wake SKIP (single CPU)"
fi
SMP_SCHED_LINE=$LIFECYCLE_LINE
for SCHED_MARKER in "$DRAIN_MARKER" "$TARGET_MARKER"; do
    NEXT_LINE=
    if [ -n "$SMP_SCHED_LINE" ]; then
        NEXT_LINE=$(awk -v after="$SMP_SCHED_LINE" -v expected="$SCHED_MARKER" \
            -v heartbeat="heartbeat #0" \
            'NR > after { sub(/\r$/, "", $0); if ($0 == heartbeat) exit; if ($0 == expected) { print NR; exit } }' "$LOG")
    fi
    if [ -z "$NEXT_LINE" ]; then
        echo "FAIL: missing exact SMP scheduler marker before first heartbeat: $SCHED_MARKER"
        PASS=0
    else
        SMP_SCHED_LINE=$NEXT_LINE
    fi
done

PREEMPT_COUNT=$(awk '{ sub(/\r$/, "", $0); if ($0 == "Scheduler preemption: PASS") count++ } END { print count + 0 }' "$LOG")
PREEMPT_LINE=$(awk '{ sub(/\r$/, "", $0); if ($0 == "Scheduler preemption: PASS") { print NR; exit } }' "$LOG")
if [ "$PREEMPT_COUNT" -ne 1 ]; then
    echo "FAIL: expected exactly one scheduler preemption PASS marker (found $PREEMPT_COUNT)"
    PASS=0
elif [ -z "$SMP_SCHED_LINE" ] || [ "$PREEMPT_LINE" -le "$SMP_SCHED_LINE" ]; then
    echo "FAIL: scheduler preemption proof did not follow SMP dispatch validation"
    PASS=0
elif ! awk -v after="$PREEMPT_LINE" \
    'NR > after { sub(/\r$/, "", $0); if ($0 ~ /^heartbeat #[0-9]+$/) found = 1 } END { exit !found }' "$LOG"; then
    echo "FAIL: no scheduler heartbeat after the preemption proof"
    PASS=0
fi

for FATAL in \
    "EARLY64 EXCEPTION" \
    "GDT verify: FAIL" \
    "VT-d: capability probe rejected" \
    "IOAPIC: topology or hardware validation FAILED" \
    "IOAPIC: PIT IRQ0 delivery FAILED" \
    "Paging verify: FAIL" \
    "IDT64 verify: FAIL" \
    "Long-mode transition verify: FAIL"
do
    if grep -Fq "$FATAL" "$LOG"; then
        echo "FAIL: fatal transition diagnostic found: $FATAL"
        PASS=0
    fi
done

if grep -Eiq '(^|[^[:alpha:]])(FAIL|FAILED|FAILURE|ERROR|FATAL|PANIC)([^[:alpha:]]|$)|page fault|triple fault' "$LOG"; then
    echo "FAIL: fatal diagnostic found in UART output"
    PASS=0
fi

if [ $PASS -eq 1 ]; then
    echo "PASS: boot test"
    exit 0
else
    exit 1
fi
