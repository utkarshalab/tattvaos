#!/bin/sh
# Assemble the real fiber and scheduler sources as one ELF object.  This gives
# fast diagnostics for trap-frame, XSAVE, queue, and lifecycle edits.

set -eu

TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$TEST_DIR/../.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM

command -v nasm >/dev/null 2>&1 || {
    echo "FAIL: nasm not found"
    exit 1
}

nasm -f elf64 -Wall -Werror -w-reloc-rel-dword -w-reloc-abs-qword \
    -w-reloc-abs-dword -w-unknown-warning \
    -I "$ROOT_DIR/" \
    "$TEST_DIR/preempt_asm_unit.asm" -o "$TMP_DIR/preempt_asm_unit.o"

test -s "$TMP_DIR/preempt_asm_unit.o" || {
    echo "FAIL: scheduler preemption object harness produced no output"
    exit 1
}

echo "PASS: scheduler trap frame, XSTATE, queue, and lifecycle sources assemble cleanly"
