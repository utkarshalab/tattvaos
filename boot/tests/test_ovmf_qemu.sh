#!/bin/sh
# Boot the real PE32+ loader and ULF kernel under QEMU/OVMF and require ordered
# UART milestones through the scheduler heartbeat.

set -eu

TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
BOOT_DIR=$(CDPATH= cd -- "$TEST_DIR/.." && pwd)
EFI_IMAGE="$BOOT_DIR/BOOTX64.EFI"
KERNEL="$BOOT_DIR/kernel.bin"
QEMU64=${QEMU:-qemu-system-x86_64}
TIMEOUT=${UEFI_BOOT_TEST_TIMEOUT:-45}
CPU=${UEFI_QEMU_CPU:-max}
SMP=${UEFI_QEMU_SMP:-1}
MACHINE=${UEFI_QEMU_MACHINE:-q35}
MEM=${UEFI_QEMU_MEM:-512}
EXPECT_HIGHMEM=${UEFI_EXPECT_HIGHMEM:-0}
EXPECT_SMP=${UEFI_EXPECT_SMP:-}
EXPECT_APIC_MODE=${UEFI_EXPECT_APIC_MODE:-}
IOMMU=${UEFI_QEMU_IOMMU:-0}
EXPECT_VTD_UNITS=${UEFI_EXPECT_VTD_UNITS:-}
EDU=${UEFI_QEMU_EDU:-0}
OVMF_CODE=${OVMF_CODE:-/usr/share/OVMF/OVMF_CODE_4M.fd}
OVMF_VARS=${OVMF_VARS:-/usr/share/OVMF/OVMF_VARS_4M.fd}
TMP_DIR=$(mktemp -d)
ESP_DIR="$TMP_DIR/esp"
LOG="$TMP_DIR/uart.log"
QEMU_ERR="$TMP_DIR/qemu.stderr"
VARS_COPY="$TMP_DIR/OVMF_VARS.fd"
trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM

case "$SMP" in
    ''|*[!0-9]*)
        echo "FAIL: invalid UEFI_QEMU_SMP value: $SMP"
        exit 1
        ;;
esac
[ "$SMP" -ge 1 ] || {
    echo "FAIL: UEFI_QEMU_SMP must be at least 1"
    exit 1
}
if [ -n "$EXPECT_SMP" ]; then
    case "$EXPECT_SMP" in
        *[!0-9]*)
            echo "FAIL: invalid UEFI_EXPECT_SMP value: $EXPECT_SMP"
            exit 1
            ;;
    esac
fi
case "$EXPECT_APIC_MODE" in
    ''|xAPIC|x2APIC) ;;
    *)
        echo "FAIL: invalid UEFI_EXPECT_APIC_MODE value: $EXPECT_APIC_MODE"
        exit 1
        ;;
esac

case "$IOMMU" in
    0|1) ;;
    *)
        echo "FAIL: invalid UEFI_QEMU_IOMMU value: $IOMMU"
        exit 1
        ;;
esac

case "$EDU" in
    0|1) ;;
    *)
        echo "FAIL: invalid UEFI_QEMU_EDU value: $EDU"
        exit 1
        ;;
esac

case "$EXPECT_VTD_UNITS" in
    '') ;;
    *[!0-9]*|0)
        echo "FAIL: invalid UEFI_EXPECT_VTD_UNITS value: $EXPECT_VTD_UNITS"
        exit 1
        ;;
esac

set --
if [ "$IOMMU" -eq 1 ]; then
    case "$MACHINE" in
        q35)
            MACHINE="$MACHINE,kernel-irqchip=split"
            ;;
        q35,*kernel-irqchip=split*|q35,*kernel-irqchip=off*) ;;
        q35,*kernel-irqchip=*)
            echo "FAIL: intel-iommu interrupt remapping requires a split or disabled kernel irqchip"
            exit 1
            ;;
        q35,*)
            MACHINE="$MACHINE,kernel-irqchip=split"
            ;;
        *)
            echo "FAIL: intel-iommu integration requires a q35 machine"
            exit 1
            ;;
    esac
    set -- "$@" -device "intel-iommu,intremap=on,eim=on"
fi
if [ "$EDU" -eq 1 ]; then
    set -- "$@" -device "edu,addr=06.0"
fi

for TOOL in "$QEMU64" timeout; do
    command -v "$TOOL" >/dev/null 2>&1 || {
        echo "FAIL: required command not found: $TOOL"
        exit 1
    }
done
for FILE in "$EFI_IMAGE" "$KERNEL" "$OVMF_CODE" "$OVMF_VARS"; do
    [ -f "$FILE" ] || {
        echo "FAIL: OVMF input not found: $FILE"
        exit 1
    }
done

mkdir -p "$ESP_DIR/EFI/BOOT"
cp "$EFI_IMAGE" "$ESP_DIR/EFI/BOOT/BOOTX64.EFI"
cp "$KERNEL" "$ESP_DIR/kernel.ulf"
cp "$OVMF_VARS" "$VARS_COPY"

ACCEL=tcg
if [ -e /dev/kvm ] && [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
    ACCEL=kvm
fi

echo "[test_ovmf_qemu] Booting PE32+ loader in OVMF..."
: > "$LOG"
: > "$QEMU_ERR"
set +e
timeout "$TIMEOUT" "$QEMU64" \
    -machine "$MACHINE" \
    -accel "$ACCEL" \
    -cpu "$CPU" \
    -smp "$SMP" \
    -m "$MEM" \
    -drive "if=pflash,format=raw,unit=0,readonly=on,file=$OVMF_CODE" \
    -drive "if=pflash,format=raw,unit=1,file=$VARS_COPY" \
    -drive "format=raw,file=fat:rw:$ESP_DIR" \
    -netdev user,id=n0 \
    -device e1000,netdev=n0 \
    "$@" \
    -serial "file:$LOG" \
    -monitor none \
    -display none \
    -no-reboot -no-shutdown \
    2>"$QEMU_ERR"
QEMU_STATUS=$?
set -e

echo "[test_ovmf_qemu] UART output:"
LINES=$(wc -l < "$LOG")
if [ "$LINES" -le 400 ]; then
    cat "$LOG"
else
    sed -n '1,240p' "$LOG"
    echo "[test_ovmf_qemu] ... $((LINES - 340)) UART lines omitted ..."
    tail -n 100 "$LOG"
fi

if [ "$QEMU_STATUS" -ne 124 ]; then
    echo "FAIL: OVMF QEMU exited before timeout (status $QEMU_STATUS)"
    [ ! -s "$QEMU_ERR" ] || cat "$QEMU_ERR"
    exit 1
fi

PASS=1
LAST_LINE=0
for MILESTONE in \
    "Tattva OS | UEFI Path OK" \
    "Tattva Kernel Booting..." \
    "CPU features verified (SSE3, AVX, AVX2, FMA)." \
    "Boot memory self-test: PASS" \
    "Tattva Kernel Ready. Entering main execution." \
    "heartbeat #0"
do
    LINE=$(awk -v after="$LAST_LINE" -v needle="$MILESTONE" \
        'NR > after && index($0, needle) { print NR; exit }' "$LOG")
    if [ -z "$LINE" ]; then
        echo "FAIL: missing or out-of-order OVMF milestone: $MILESTONE"
        PASS=0
    else
        LAST_LINE=$LINE
    fi
done

if [ "$EXPECT_HIGHMEM" -eq 1 ]; then
    for MILESTONE in \
        "Paging high map verify: OK" \
        "Highmem direct-map R/W: PASS phys=0x00000001"
    do
        grep -Fq "$MILESTONE" "$LOG" || {
            echo "FAIL: missing forced-high-memory OVMF milestone: $MILESTONE"
            PASS=0
        }
    done
    if grep -Fq "Highmem direct-map R/W: SKIP" "$LOG"; then
        echo "FAIL: OVMF left supported high RAM offline"
        PASS=0
    fi
else
    for MILESTONE in \
        "Paging high map verify: SKIP (no supported RAM above 4 GiB)" \
        "Highmem direct-map R/W: SKIP (no supported RAM above 4 GiB)"
    do
        grep -Fq "$MILESTONE" "$LOG" || {
            echo "FAIL: missing no-high-memory OVMF milestone: $MILESTONE"
            PASS=0
        }
    done
    if grep -Fq "Paging high map verify: OK" "$LOG" || \
       grep -Fq "Highmem direct-map R/W: PASS" "$LOG"; then
        echo "FAIL: ordinary OVMF boot unexpectedly published high RAM"
        PASS=0
    fi
fi

if ! grep -Eq 'BootInfo Pointer: 0x[0-9A-F]{16}' "$LOG"; then
    echo "FAIL: UEFI BootInfo pointer was not rendered as a 64-bit address"
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
    if grep -Fq "SMP: disabled by validation code" "$LOG"; then
        echo "FAIL: SMP topology fell back to BSP-only mode"
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

if [ -n "$EXPECT_VTD_UNITS" ]; then
    VTD_MARKER="VT-d: $EXPECT_VTD_UNITS remapping units support interrupt remapping"
    if ! awk -v expected="$VTD_MARKER" \
        '{ sub(/\r$/, "", $0); if ($0 == expected) found = 1 } END { exit !found }' "$LOG"; then
        echo "FAIL: missing exact VT-d capability marker: $VTD_MARKER"
        PASS=0
    fi
    if grep -Eq '^VT-d: .* (disabled|rejected)' "$LOG"; then
        echo "FAIL: VT-d integration boot did not retain remapping readiness"
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

INTERRUPT_LINE=$IOAPIC_LINE
if [ "$EDU" -eq 1 ]; then
    MSI_MARKER="PCI MSI: EDU one-shot PASS"
    MSI_COUNT=$(awk -v expected="$MSI_MARKER" '{ sub(/\r$/, "", $0); if ($0 == expected) count++ } END { print count + 0 }' "$LOG")
    MSI_LINE=
    if [ -n "$IOAPIC_LINE" ]; then
        MSI_LINE=$(awk -v after="$IOAPIC_LINE" -v expected="$MSI_MARKER" -v heartbeat="heartbeat #0" 'NR > after { sub(/\r$/, "", $0); if ($0 == heartbeat) exit; if ($0 == expected) { print NR; exit } }' "$LOG")
    fi
    if [ "$MSI_COUNT" -ne 1 ] || [ -z "$MSI_LINE" ]; then
        echo "FAIL: expected exactly one EDU MSI proof after IOAPIC delivery"
        PASS=0
    else
        INTERRUPT_LINE=$MSI_LINE
    fi
fi

if [ "$TIMER_CPUS" -gt 1 ]; then
    LIFECYCLE_MARKER="SMP: scheduler park/unpark PASS"
else
    LIFECYCLE_MARKER="SMP: scheduler park/unpark SKIP (single CPU)"
fi
LIFECYCLE_LINE=
if [ -n "$INTERRUPT_LINE" ]; then
    LIFECYCLE_LINE=$(awk -v after="$INTERRUPT_LINE" -v expected="$LIFECYCLE_MARKER" \
        -v heartbeat="heartbeat #0" \
        'NR > after { sub(/\r$/, "", $0); if ($0 == heartbeat) exit; if ($0 == expected) { print NR; exit } }' "$LOG")
fi
if [ -z "$LIFECYCLE_LINE" ]; then
    echo "FAIL: missing exact scheduler lifecycle marker after external-interrupt proofs: $LIFECYCLE_MARKER"
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
    "UEFI TRANSITION EXCEPTION" \
    "EARLY64 EXCEPTION" \
    "KERNEL PANIC" \
    "VT-d: capability probe rejected" \
    "IOAPIC: topology or hardware validation FAILED" \
    "IOAPIC: PIT IRQ0 delivery FAILED" \
    "PCI MSI: EDU one-shot FAILED" \
    "Scheduler preemption: FAIL" \
    "SMP: scheduler park/unpark FAILED" \
    "ERROR: Failed to load kernel.ulf" \
    "ERROR: Failed to get memory map" \
    "ERROR: Final UEFI handoff validation failed" \
    "ERROR: Failed to prepare owned kernel transition"
do
    if grep -Fq "$FATAL" "$LOG"; then
        echo "FAIL: fatal UEFI diagnostic found: $FATAL"
        PASS=0
    fi
done

if [ "$PASS" -eq 1 ]; then
    echo "PASS: OVMF UEFI boot reached a live kernel scheduler"
    exit 0
fi
exit 1
