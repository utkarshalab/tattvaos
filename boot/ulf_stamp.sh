#!/bin/sh
# =============================================================================
# Utkarsha OS — boot/ulf_stamp.sh
# =============================================================================
# Validates the ULF v2 layout and fills in the two header fields the assembler
# cannot produce.
#
#   +4  (dd)  image length in bytes
#             nasm's kernel_end label sits in .text, and .data/.rodata are
#             emitted after it in a flat binary, so the label measures the text
#             extent only — it reported a 9.3MB image as 274KB. A loader
#             trusting that would copy the code and none of its data.
#
#   +16 (dq)  checksum
#             Sum of every quadword in the image mod 2^64, with the checksum
#             quadword itself counted as zero. boot/stage2/cpu/longmode.asm
#             recomputes this before jumping and halts on a mismatch, which is
#             what catches a short or corrupt read of the ~19000-sector image
#             across ~300 BIOS calls.
#
# Not Python: this is an assembly-native OS and building the kernel should not
# require an interpreter. od renders the image as unsigned 32-bit words, awk
# sums the low and high halves of each quadword separately so no intermediate
# leaves the range a double represents exactly, and dd writes the bytes back.
# =============================================================================

set -e

IMG="$1"
if [ -z "$IMG" ] || [ ! -f "$IMG" ]; then
    echo "usage: ulf_stamp.sh <ulf-image>" >&2
    exit 1
fi

# -----------------------------------------------------------------------------
# write_le32 <value> <byte-offset> — patch four little-endian bytes in place
# -----------------------------------------------------------------------------
write_le32() {
    printf "$(printf '\\%03o\\%03o\\%03o\\%03o' \
        $(( $1 % 256 )) $(( $1 / 256 % 256 )) \
        $(( $1 / 65536 % 256 )) $(( $1 / 16777216 % 256 )))" \
      | dd of="$IMG" bs=1 seek="$2" conv=notrunc status=none
}

# -----------------------------------------------------------------------------
# 1. Size. The loader rejects a length that is not a multiple of 8, because its
#    checksum walks the image a quadword at a time.
# -----------------------------------------------------------------------------
SZ=$(wc -c < "$IMG")
SZ=$(( SZ ))
if [ "$SZ" -lt 40 ] || [ "$SZ" -gt $((32 * 1024 * 1024)) ]; then
    echo "ulf: image size $SZ is outside v2 bounds" >&2
    exit 1
fi
if [ $(( SZ % 8 )) -ne 0 ]; then
    echo "ulf: image is $SZ bytes, not a multiple of 8" >&2
    exit 1
fi

# The executable prefix is assembler-owned metadata. Refuse to bless an image
# whose version or boundary would merge code and writable data in one page.
ULF_MAGIC=$(od -An -tu4 -j0 -N4 "$IMG" | tr -d '[:space:]')
ENTRY=$(od -An -tu8 -j8 -N8 "$IMG" | tr -d '[:space:]')
EXEC_SIZE=$(od -An -tu4 -j24 -N4 "$IMG" | tr -d '[:space:]')
ULF_VERSION=$(od -An -tu4 -j28 -N4 "$IMG" | tr -d '[:space:]')
MEM_SIZE=$(od -An -tu8 -j32 -N8 "$IMG" | tr -d '[:space:]')
if [ "$ULF_MAGIC" -ne $((0x00464C55)) ]; then
    echo "ulf: invalid magic $ULF_MAGIC" >&2
    exit 1
fi
if [ "$ULF_VERSION" -ne 2 ]; then
    echo "ulf: unsupported header version $ULF_VERSION" >&2
    exit 1
fi
if [ "$EXEC_SIZE" -lt 40 ] || [ "$EXEC_SIZE" -gt $((1024 * 1024)) ] || [ "$EXEC_SIZE" -gt "$SZ" ] || [ $((EXEC_SIZE % 4096)) -ne 0 ]; then
    echo "ulf: invalid executable extent $EXEC_SIZE" >&2
    exit 1
fi
if [ "$ENTRY" -lt $((0x100000 + 40)) ] || [ "$ENTRY" -ge $((0x100000 + EXEC_SIZE)) ]; then
    echo "ulf: entry point $ENTRY is outside the executable extent" >&2
    exit 1
fi
if [ "$MEM_SIZE" -lt "$SZ" ] || [ "$MEM_SIZE" -gt $((64 * 1024 * 1024)) ] || [ $((MEM_SIZE % 8)) -ne 0 ]; then
    echo "ulf: invalid memory extent $MEM_SIZE for $SZ-byte image" >&2
    exit 1
fi
write_le32 "$SZ" 4

# -----------------------------------------------------------------------------
# 2. Checksum. Must run after the size is written — the size field is inside
#    the region being summed.
# -----------------------------------------------------------------------------
SUM=$(od -An -tu4 -v -w8 "$IMG" | awk '
    {
        lo = $1; hi = $2
        if (NR == 3) { lo = 0; hi = 0 }   # the checksum quadword, offset 16
        tl += lo
        th += hi
        if (tl >= 4294967296) { tl -= 4294967296; th += 1 }
        if (th >= 4294967296) { th -= 4294967296 }
    }
    END { printf "%d %d\n", tl, th }
')

write_le32 "${SUM% *}" 16
write_le32 "${SUM#* }" 20

printf 'ulf: %s bytes, checksum %08x%08x\n' \
    "$SZ" "${SUM#* }" "${SUM% *}" 2>/dev/null || true
