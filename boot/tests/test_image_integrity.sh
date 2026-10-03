#!/bin/sh
# Validate the exact disk-layout and integrity contracts shared by the
# Makefile, stage1, stage2, and the ULF kernel loader.

set -eu

TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
BOOT_DIR=$(CDPATH= cd -- "$TEST_DIR/.." && pwd)
STAGE1="$BOOT_DIR/stage1.bin"
STAGE2="$BOOT_DIR/stage2.bin"
KERNEL="$BOOT_DIR/kernel.bin"
IMAGE="$BOOT_DIR/tattva.img"

fail() {
    echo "FAIL: $*"
    exit 1
}

for FILE in "$STAGE1" "$STAGE2" "$KERNEL" "$IMAGE"; do
    [ -f "$FILE" ] || fail "missing artifact: $FILE"
done

hex_at() {
    od -An -tx1 -j"$2" -N"$3" "$1" | tr -d ' \n'
}

STAGE2_MAGIC=$(hex_at "$STAGE2" 0 4)
[ "$STAGE2_MAGIC" = "42545332" ] || \
    fail "stage2 magic is $STAGE2_MAGIC, expected 42545332 (BTS2)"

ULF_MAGIC=$(hex_at "$KERNEL" 0 4)
[ "$ULF_MAGIC" = "554c4600" ] || \
    fail "kernel magic is $ULF_MAGIC, expected 554c4600 (ULF\\0)"

KERNEL_SIZE=$(wc -c < "$KERNEL" | tr -d ' ')
HEADER_SIZE=$(od -An -tu4 -j4 -N4 "$KERNEL" | tr -d ' ')
[ "$HEADER_SIZE" = "$KERNEL_SIZE" ] || \
    fail "ULF size field is $HEADER_SIZE, file is $KERNEL_SIZE bytes"
[ "$KERNEL_SIZE" -ge 32 ] && [ "$KERNEL_SIZE" -le $((32 * 1024 * 1024)) ] || \
    fail "kernel size is outside loader bounds: $KERNEL_SIZE"
[ $((KERNEL_SIZE % 8)) -eq 0 ] || \
    fail "kernel size is not checksum-aligned: $KERNEL_SIZE"

ULF_ENTRY=$(od -An -tu8 -j8 -N8 "$KERNEL" | tr -d ' ')
ULF_EXEC_SIZE=$(od -An -tu4 -j24 -N4 "$KERNEL" | tr -d ' ')
ULF_VERSION=$(od -An -tu4 -j28 -N4 "$KERNEL" | tr -d ' ')
[ "$ULF_VERSION" -eq 1 ] || fail "unsupported ULF version: $ULF_VERSION"
[ "$ULF_EXEC_SIZE" -ge 32 ] && [ "$ULF_EXEC_SIZE" -le $((1024 * 1024)) ] && \
    [ "$ULF_EXEC_SIZE" -le "$KERNEL_SIZE" ] || \
    fail "ULF executable extent is invalid: $ULF_EXEC_SIZE"
if [ $((ULF_EXEC_SIZE % 4096)) -ne 0 ]; then
    fail "ULF executable extent is not page-aligned: $ULF_EXEC_SIZE"
fi
[ "$ULF_ENTRY" -ge $((0x100000 + 32)) ] && \
    [ "$ULF_ENTRY" -lt $((0x100000 + ULF_EXEC_SIZE)) ] || \
    fail "ULF entry point is outside the executable extent: $ULF_ENTRY"

# Recompute the same modulo-2^64 quadword sum as ulf_stamp.sh, treating the
# checksum field itself as zero.
set -- $(od -An -tu4 -v -w8 "$KERNEL" | awk '
    {
        lo = $1; hi = $2
        if (NR == 3) { lo = 0; hi = 0 }
        tl += lo
        th += hi
        if (tl >= 4294967296) { tl -= 4294967296; th += 1 }
        if (th >= 4294967296) { th -= 4294967296 }
    }
    END { printf "%.0f %.0f\n", tl, th }
')
STORED_LO=$(od -An -tu4 -j16 -N4 "$KERNEL" | tr -d ' ')
STORED_HI=$(od -An -tu4 -j20 -N4 "$KERNEL" | tr -d ' ')
[ "$1" = "$STORED_LO" ] && [ "$2" = "$STORED_HI" ] || \
    fail "ULF checksum mismatch (computed $2:$1, stored $STORED_HI:$STORED_LO)"

IMAGE_STAGE1=$(hex_at "$IMAGE" 0 512)
FILE_STAGE1=$(hex_at "$STAGE1" 0 512)
[ "$IMAGE_STAGE1" = "$FILE_STAGE1" ] || fail "image LBA 0 differs from stage1.bin"

IMAGE_STAGE2_MAGIC=$(hex_at "$IMAGE" 512 4)
[ "$IMAGE_STAGE2_MAGIC" = "$STAGE2_MAGIC" ] || \
    fail "image LBA 1 does not contain stage2"

FILE_ULF_HEADER=$(hex_at "$KERNEL" 0 32)
IMAGE_ULF_HEADER=$(hex_at "$IMAGE" $((65 * 512)) 32)
[ "$IMAGE_ULF_HEADER" = "$FILE_ULF_HEADER" ] || \
    fail "image LBA 65 ULF v1 header differs from kernel.bin"

IMAGE_SECTORS=$(( ($(wc -c < "$IMAGE") + 511) / 512 ))
KERNEL_END_LBA=$((65 + (KERNEL_SIZE + 511) / 512))
[ "$KERNEL_END_LBA" -le "$IMAGE_SECTORS" ] || \
    fail "ULF extent ends at LBA $KERNEL_END_LBA beyond image sector $IMAGE_SECTORS"

echo "PASS: image layout and ULF integrity contracts"
