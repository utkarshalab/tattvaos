#!/bin/sh
# =============================================================================
# Tattva OS — boot/ulf_stamp.sh
# =============================================================================
# Fills in the two ULF header fields the assembler cannot produce.
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
if [ $(( SZ % 8 )) -ne 0 ]; then
    echo "ulf: image is $SZ bytes, not a multiple of 8" >&2
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
