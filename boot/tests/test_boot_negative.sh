#!/bin/sh
# Verify that corrupted boot artifacts and unsupported CPUs fail closed, plus
# one focused no-NX compatibility boot.  Every mutation is made in a private
# temporary copy of utkarsha.img.

set -eu

TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
GOOD_IMAGE="$TEST_DIR/../utkarsha.img"
QEMU64=${QEMU:-qemu-system-x86_64}
TIMEOUT=${BOOT_NEGATIVE_TIMEOUT:-12}
KERNEL_OFFSET=$((65 * 512))
COMPAT_TIMEOUT=$(printenv BOOT_COMPAT_TIMEOUT 2>/dev/null || true)
[ -n "$COMPAT_TIMEOUT" ] || COMPAT_TIMEOUT=30
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM

fail() {
    echo "FAIL: $*"
    exit 1
}

[ -f "$GOOD_IMAGE" ] || fail "image not found: $GOOD_IMAGE"
command -v "$QEMU64" >/dev/null 2>&1 || fail "QEMU not found: $QEMU64"
command -v timeout >/dev/null 2>&1 || fail "timeout command not found"

run_guest() {
    IMAGE=$1
    CPU=$2
    LOG=$3
    RUN_TIMEOUT=$TIMEOUT
    [ "$#" -lt 4 ] || RUN_TIMEOUT=$4
    QEMU_ERR="$LOG.stderr"
    : > "$LOG"
    : > "$QEMU_ERR"
    set +e
    timeout "$RUN_TIMEOUT" "$QEMU64" \
        -drive "format=raw,file=$IMAGE" \
        -cpu "$CPU" \
        -m 512 \
        -netdev user,id=n0 \
        -device e1000,netdev=n0 \
        -serial "file:$LOG" \
        -no-reboot -no-shutdown -display none \
        2>"$QEMU_ERR"
    QEMU_STATUS=$?
    set -e

    # Every negative case is required to halt in its explicit fail-closed loop.
    # A reset/triple fault or a QEMU setup failure exits before timeout instead.
    if [ "$QEMU_STATUS" -ne 124 ]; then
        echo "FAIL: QEMU exited early for $(basename "$IMAGE") (status $QEMU_STATUS)"
        if [ -s "$QEMU_ERR" ]; then
            echo "QEMU stderr:"
            cat "$QEMU_ERR"
        fi
        exit 1
    fi
}

expect_line() {
    NAME=$1
    PATTERN=$2
    LOG=$3
    grep -Fq "$PATTERN" "$LOG" || fail "$NAME did not report: $PATTERN"
    echo "PASS: $NAME"
}

expect_absent() {
    NAME=$1
    PATTERN=$2
    LOG=$3
    if grep -Fq "$PATTERN" "$LOG"; then
        fail "$NAME unexpectedly reported: $PATTERN"
    fi
}

expect_ordered_lines() {
    NAME=$1
    LOG=$2
    shift 2
    LAST_LINE=0
    for PATTERN do
        LINE=$(awk -v after="$LAST_LINE" -v needle="$PATTERN" \
            'NR > after && index($0, needle) { print NR; exit }' "$LOG")
        [ -n "$LINE" ] || fail "$NAME missing or out of order: $PATTERN"
        LAST_LINE=$LINE
    done
    echo "PASS: $NAME"
}

write_le32() {
    FILE=$1
    OFFSET=$2
    VALUE=$3
    printf "$(printf '\\%03o\\%03o\\%03o\\%03o' \
        $((VALUE % 256)) $((VALUE / 256 % 256)) \
        $((VALUE / 65536 % 256)) $((VALUE / 16777216 % 256)))" | \
        dd of="$FILE" bs=1 seek="$OFFSET" conv=notrunc status=none
}

# A disk containing only the MBR forces every AH=42h attempt to fail.  Stage1
# must exhaust its bounded retry loop and remain on its fatal path.
SHORT_DISK="$TMP_DIR/short.img"
dd if="$GOOD_IMAGE" of="$SHORT_DISK" bs=512 count=1 status=none
SHORT_LOG="$TMP_DIR/short.log"
run_guest "$SHORT_DISK" max "$SHORT_LOG"
expect_line "truncated boot disk rejected after retries" "Disk err" "$SHORT_LOG"

# Stage1 mirrors fatal diagnostics to COM1 so headless boots are observable.
STAGE2_BAD="$TMP_DIR/stage2-bad.img"
cp "$GOOD_IMAGE" "$STAGE2_BAD"
printf '\000\000\000\000' | dd of="$STAGE2_BAD" bs=1 seek=512 conv=notrunc status=none
STAGE2_LOG="$TMP_DIR/stage2.log"
run_guest "$STAGE2_BAD" max "$STAGE2_LOG"
[ "$(od -An -tx1 -j512 -N4 "$STAGE2_BAD" | tr -d ' \n')" = "00000000" ] || \
    fail "stage2 mutation was not written"
expect_line "corrupt stage2 rejected before stage2 entry" "Bad magic" "$STAGE2_LOG"

ULF_MAGIC_BAD="$TMP_DIR/ulf-magic-bad.img"
cp "$GOOD_IMAGE" "$ULF_MAGIC_BAD"
printf '\000\000\000\000' | dd of="$ULF_MAGIC_BAD" bs=1 seek="$KERNEL_OFFSET" conv=notrunc status=none
ULF_MAGIC_LOG="$TMP_DIR/ulf-magic.log"
run_guest "$ULF_MAGIC_BAD" max "$ULF_MAGIC_LOG"
expect_line "invalid ULF magic rejected" "FAIL (no ULF magic at kernel LBA)" "$ULF_MAGIC_LOG"
expect_absent "non-disk ULF failure" "BIOS status" "$ULF_MAGIC_LOG"

ULF_SIZE_BAD="$TMP_DIR/ulf-size-bad.img"
cp "$GOOD_IMAGE" "$ULF_SIZE_BAD"
printf '\020\000\000\000' | dd of="$ULF_SIZE_BAD" bs=1 seek=$((KERNEL_OFFSET + 4)) conv=notrunc status=none
ULF_SIZE_LOG="$TMP_DIR/ulf-size.log"
run_guest "$ULF_SIZE_BAD" max "$ULF_SIZE_LOG"
expect_line "invalid ULF size rejected" "FAIL (implausible ULF image size)" "$ULF_SIZE_LOG"

ULF_ALIGN_BAD="$TMP_DIR/ulf-align-bad.img"
cp "$GOOD_IMAGE" "$ULF_ALIGN_BAD"
printf '\041\000\000\000' | dd of="$ULF_ALIGN_BAD" bs=1 seek=$((KERNEL_OFFSET + 4)) conv=notrunc status=none
ULF_ALIGN_LOG="$TMP_DIR/ulf-align.log"
run_guest "$ULF_ALIGN_BAD" max "$ULF_ALIGN_LOG"
expect_line "unaligned ULF size rejected" "FAIL (implausible ULF image size)" "$ULF_ALIGN_LOG"

ULF_ENTRY_BAD="$TMP_DIR/ulf-entry-bad.img"
cp "$GOOD_IMAGE" "$ULF_ENTRY_BAD"
printf '\000\000\000\000\000\000\000\000' | \
    dd of="$ULF_ENTRY_BAD" bs=1 seek=$((KERNEL_OFFSET + 8)) conv=notrunc status=none
ULF_ENTRY_LOG="$TMP_DIR/ulf-entry.log"
run_guest "$ULF_ENTRY_BAD" max "$ULF_ENTRY_LOG"
expect_line "out-of-image ULF entry rejected" "FAIL (invalid ULF entry point)" "$ULF_ENTRY_LOG"

ULF_VERSION_BAD="$TMP_DIR/ulf-version-bad.img"
cp "$GOOD_IMAGE" "$ULF_VERSION_BAD"
printf '\001\000\000\000' | \
    dd of="$ULF_VERSION_BAD" bs=1 seek=$((KERNEL_OFFSET + 28)) conv=notrunc status=none
ULF_VERSION_LOG="$TMP_DIR/ulf-version.log"
run_guest "$ULF_VERSION_BAD" max "$ULF_VERSION_LOG"
expect_line "unsupported ULF version rejected" "FAIL (unsupported ULF header)" "$ULF_VERSION_LOG"

ULF_EXEC_BAD="$TMP_DIR/ulf-exec-bad.img"
cp "$GOOD_IMAGE" "$ULF_EXEC_BAD"
printf '\010\000\000\000' | \
    dd of="$ULF_EXEC_BAD" bs=1 seek=$((KERNEL_OFFSET + 24)) conv=notrunc status=none
ULF_EXEC_LOG="$TMP_DIR/ulf-exec.log"
run_guest "$ULF_EXEC_BAD" max "$ULF_EXEC_LOG"
expect_line "invalid ULF executable extent rejected" "FAIL (unsupported ULF header)" "$ULF_EXEC_LOG"

ULF_EXEC_ALIGN_BAD="$TMP_DIR/ulf-exec-align-bad.img"
cp "$GOOD_IMAGE" "$ULF_EXEC_ALIGN_BAD"
write_le32 "$ULF_EXEC_ALIGN_BAD" $((KERNEL_OFFSET + 24)) 40
ULF_EXEC_ALIGN_LOG="$TMP_DIR/ulf-exec-align.log"
run_guest "$ULF_EXEC_ALIGN_BAD" max "$ULF_EXEC_ALIGN_LOG"
expect_line "unaligned ULF executable extent rejected" "FAIL (unsupported ULF header)" "$ULF_EXEC_ALIGN_LOG"

# ULF v2 retains the executable-prefix cap at the 1MB PT0 kernel window. Exercise
# the upper bound independently of the too-small extent case above.
ULF_EXEC_LARGE_BAD="$TMP_DIR/ulf-exec-large-bad.img"
cp "$GOOD_IMAGE" "$ULF_EXEC_LARGE_BAD"
write_le32 "$ULF_EXEC_LARGE_BAD" $((KERNEL_OFFSET + 24)) $((1024 * 1024 + 4096))
ULF_EXEC_LARGE_LOG="$TMP_DIR/ulf-exec-large.log"
run_guest "$ULF_EXEC_LARGE_BAD" max "$ULF_EXEC_LARGE_LOG"
expect_line "oversized ULF executable extent rejected" "FAIL (unsupported ULF header)" "$ULF_EXEC_LARGE_LOG"

# The executable extent is half-open.  An entry exactly at its end must not be
# accepted and allowed to fault on the first NX data page.
ULF_EXEC_SIZE=$(od -An -tu4 -j$((KERNEL_OFFSET + 24)) -N4 "$GOOD_IMAGE" | tr -d ' ')
ULF_ENTRY_AT_END=$((0x100000 + ULF_EXEC_SIZE))
ULF_ENTRY_END_BAD="$TMP_DIR/ulf-entry-at-exec-end.img"
cp "$GOOD_IMAGE" "$ULF_ENTRY_END_BAD"
write_le32 "$ULF_ENTRY_END_BAD" $((KERNEL_OFFSET + 8)) "$ULF_ENTRY_AT_END"
write_le32 "$ULF_ENTRY_END_BAD" $((KERNEL_OFFSET + 12)) 0
ULF_ENTRY_END_LOG="$TMP_DIR/ulf-entry-at-exec-end.log"
run_guest "$ULF_ENTRY_END_BAD" max "$ULF_ENTRY_END_LOG"
expect_line "ULF entry at executable boundary rejected" "FAIL (invalid ULF entry point)" "$ULF_ENTRY_END_LOG"

# ULF v2 owns and zeroes the complete memory footprint.  Reject both a range
# that cannot contain the file and one beyond the loader's bounded policy
# before either value can influence a destination or zeroing loop.
ULF_MEMORY_SMALL_BAD="$TMP_DIR/ulf-memory-small.img"
cp "$GOOD_IMAGE" "$ULF_MEMORY_SMALL_BAD"
write_le32 "$ULF_MEMORY_SMALL_BAD" $((KERNEL_OFFSET + 32)) 40
write_le32 "$ULF_MEMORY_SMALL_BAD" $((KERNEL_OFFSET + 36)) 0
ULF_MEMORY_SMALL_LOG="$TMP_DIR/ulf-memory-small.log"
run_guest "$ULF_MEMORY_SMALL_BAD" max "$ULF_MEMORY_SMALL_LOG"
expect_line "undersized ULF memory extent rejected" "FAIL (unsupported ULF header)" "$ULF_MEMORY_SMALL_LOG"

ULF_MEMORY_LARGE_BAD="$TMP_DIR/ulf-memory-large.img"
cp "$GOOD_IMAGE" "$ULF_MEMORY_LARGE_BAD"
write_le32 "$ULF_MEMORY_LARGE_BAD" $((KERNEL_OFFSET + 32)) $((64 * 1024 * 1024 + 8))
write_le32 "$ULF_MEMORY_LARGE_BAD" $((KERNEL_OFFSET + 36)) 0
ULF_MEMORY_LARGE_LOG="$TMP_DIR/ulf-memory-large.log"
run_guest "$ULF_MEMORY_LARGE_BAD" max "$ULF_MEMORY_LARGE_LOG"
expect_line "oversized ULF memory extent rejected" "FAIL (unsupported ULF header)" "$ULF_MEMORY_LARGE_LOG"

ULF_MEMORY_HIGH_BAD="$TMP_DIR/ulf-memory-high.img"
cp "$GOOD_IMAGE" "$ULF_MEMORY_HIGH_BAD"
write_le32 "$ULF_MEMORY_HIGH_BAD" $((KERNEL_OFFSET + 36)) 1
ULF_MEMORY_HIGH_LOG="$TMP_DIR/ulf-memory-high.log"
run_guest "$ULF_MEMORY_HIGH_BAD" max "$ULF_MEMORY_HIGH_LOG"
expect_line "high ULF memory extent rejected" "FAIL (unsupported ULF header)" "$ULF_MEMORY_HIGH_LOG"

# Preserve a valid header but remove nearly all of the declared kernel image.
# The EDD capacity check must reject it before the destination is half-written.
ULF_TRUNCATED="$TMP_DIR/ulf-truncated.img"
dd if="$GOOD_IMAGE" of="$ULF_TRUNCATED" bs=512 count=$((65 + 8)) status=none
ULF_TRUNCATED_LOG="$TMP_DIR/ulf-truncated.log"
run_guest "$ULF_TRUNCATED" max "$ULF_TRUNCATED_LOG"
expect_line "truncated ULF extent rejected" "FAIL (ULF image exceeds disk)" "$ULF_TRUNCATED_LOG"

ULF_SUM_BAD="$TMP_DIR/ulf-checksum-bad.img"
cp "$GOOD_IMAGE" "$ULF_SUM_BAD"
printf '\000\000\000\000\000\000\000\000' | \
    dd of="$ULF_SUM_BAD" bs=1 seek=$((KERNEL_OFFSET + 16)) conv=notrunc status=none
ULF_SUM_LOG="$TMP_DIR/ulf-checksum.log"
# Unlike the header-only rejects above, this path sums the complete ULF under
# emulation before it can report the mismatch.
run_guest "$ULF_SUM_BAD" max "$ULF_SUM_LOG" "$COMPAT_TIMEOUT"
expect_line "invalid ULF checksum rejected" "FAIL (Bad Checksum)" "$ULF_SUM_LOG"

CPU_LOG="$TMP_DIR/cpu.log"
run_guest "$GOOD_IMAGE" qemu64 "$CPU_LOG" "$COMPAT_TIMEOUT"
expect_line "unsupported CPU rejected" "KERNEL PANIC: Missing CPU feature:" "$CPU_LOG"

# Compatibility coverage for CPUs without NX.  Stage2 must leave every entry's
# NX bit clear, keep EFER.NXE clear, and still complete the transition.  Check
# only the security-sensitive handoff markers rather than duplicating the full
# positive smoke suite here.
NO_NX_LOG="$TMP_DIR/no-nx.log"
run_guest "$GOOD_IMAGE" "max,-nx" "$NO_NX_LOG" "$COMPAT_TIMEOUT"
expect_ordered_lines "NX-less CPU compatibility boot" "$NO_NX_LOG" \
    "Paging verify: OK" \
    "IDT64 verify: OK" \
    "Long-mode transition verify: OK" \
    "CPU does not support NX" \
    "Boot memory self-test: PASS" \
    "Utkarsha Kernel Ready. Entering main execution." \
    "heartbeat #0"
expect_absent "NX-less CPU early exception" "EARLY64 EXCEPTION" "$NO_NX_LOG"
expect_absent "NX-less CPU stage2 fatal" "FATAL: stage2" "$NO_NX_LOG"
expect_absent "NX-less CPU paging failure" "Paging verify: FAIL" "$NO_NX_LOG"
expect_absent "NX-less CPU IDT64 failure" "IDT64 verify: FAIL" "$NO_NX_LOG"
expect_absent "NX-less CPU transition failure" "Long-mode transition verify: FAIL" "$NO_NX_LOG"
if grep -Eiq '(^|[^[:alpha:]])(FAIL|FAILED|FAILURE|ERROR|FATAL|PANIC)([^[:alpha:]]|$)|page fault|triple fault' "$NO_NX_LOG"; then
    fail "NX-less CPU compatibility boot reported a fatal diagnostic"
fi

echo "PASS: all negative and compatibility boot tests"
