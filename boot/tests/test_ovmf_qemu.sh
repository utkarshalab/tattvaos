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
OVMF_CODE=${OVMF_CODE:-/usr/share/OVMF/OVMF_CODE_4M.fd}
OVMF_VARS=${OVMF_VARS:-/usr/share/OVMF/OVMF_VARS_4M.fd}
TMP_DIR=$(mktemp -d)
ESP_DIR="$TMP_DIR/esp"
LOG="$TMP_DIR/uart.log"
QEMU_ERR="$TMP_DIR/qemu.stderr"
VARS_COPY="$TMP_DIR/OVMF_VARS.fd"
trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM

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
    -machine q35 \
    -accel "$ACCEL" \
    -cpu max \
    -m 512 \
    -drive "if=pflash,format=raw,unit=0,readonly=on,file=$OVMF_CODE" \
    -drive "if=pflash,format=raw,unit=1,file=$VARS_COPY" \
    -drive "format=raw,file=fat:rw:$ESP_DIR" \
    -netdev user,id=n0 \
    -device e1000,netdev=n0 \
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

if ! grep -Eq 'BootInfo Pointer: 0x[0-9A-F]{16}' "$LOG"; then
    echo "FAIL: UEFI BootInfo pointer was not rendered as a 64-bit address"
    PASS=0
fi

for FATAL in \
    "UEFI TRANSITION EXCEPTION" \
    "EARLY64 EXCEPTION" \
    "KERNEL PANIC" \
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
