#!/bin/sh
# boot/tests/test_stage1_size.sh
# Verify the complete MBR is exactly one sector with a valid BIOS signature.
# Run automatically by Makefile — fails build if over limit

set -eu

TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
STAGE1_BIN="$TEST_DIR/../stage1.bin"
EXPECTED=512

if [ ! -f "$STAGE1_BIN" ]; then
    echo "FAIL: $STAGE1_BIN not found — run make first"
    exit 1
fi

SIZE=$(wc -c < "$STAGE1_BIN")

if [ "$SIZE" -ne "$EXPECTED" ]; then
    echo "FAIL: stage1 is $SIZE bytes, expected exactly $EXPECTED"
    exit 1
fi

SIGNATURE=$(od -An -tx1 -j510 -N2 "$STAGE1_BIN" | tr -d ' \n')
if [ "$SIGNATURE" != "55aa" ]; then
    echo "FAIL: stage1 has invalid MBR signature: $SIGNATURE"
    exit 1
fi

# The first far jump in stage1 must enter the preserved copy below 0x0800.
# This catches the old ORG bug where `jmp 0:relocated_entry` encoded a target
# back in the original 0x7C00 sector even though 512 bytes had been copied.
command -v ndisasm >/dev/null 2>&1 || {
    echo "FAIL: ndisasm is required to verify the relocation target"
    exit 1
}

RELOC_TARGET=$(ndisasm -b 16 "$STAGE1_BIN" | awk '
    $3 == "jmp" && $4 ~ /^0x0:/ {
        split($4, address, ":")
        print address[2]
        exit
    }
')

STAGE2_TARGET=$(ndisasm -b 16 "$STAGE1_BIN" | awk '
    $3 == "jmp" && $4 ~ /^0x0:/ {
        count++
        if (count == 2) {
            split($4, address, ":")
            print address[2]
            exit
        }
    }
')

case "$RELOC_TARGET" in
    0x6??|0x7??|0x06??|0x07??) ;;
    *)
        echo "FAIL: stage1 far jump does not enter relocated copy: ${RELOC_TARGET:-missing}"
        exit 1
        ;;
esac

if [ "$STAGE2_TARGET" != "0x8004" ]; then
    echo "FAIL: stage1 handoff target is ${STAGE2_TARGET:-missing}, expected 0x8004"
    exit 1
fi

echo "PASS: stage1 is 512 bytes, signature 55aa, jumps to $RELOC_TARGET then $STAGE2_TARGET"
exit 0
