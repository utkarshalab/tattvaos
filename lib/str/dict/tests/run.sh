#!/bin/bash
# =============================================================================
# Tattva OS — str/dict/tests/run.sh
# =============================================================================
# Builds and runs the dict semantic suite as a hosted Linux binary.
#
# Unlike security/usrauth's suite, nothing here is doubled: the dictionary is
# static data plus pure functions, so the exact same include this file pulls
# in is what the kernel would include via dict/dict.asm.
#
# Usage:  bash lib/str/dict/tests/run.sh
# =============================================================================
set -u

ROOT=$(cd "$(dirname "$0")/../../../.." && pwd)
cd "$ROOT" || exit 1

BUILD=${TMPDIR:-/tmp}/dict_test
mkdir -p "$BUILD"

cat > "$BUILD/root.asm" <<'ASM'
[BITS 64]
%include "dict/dict.asm"
%include "dict/tests/dict_test.asm"
ASM

# lib/str's own files %include each other with str-root-relative paths (e.g.
# "arch/common/types.inc") that NASM only resolves via -I, not automatically
# relative to the including file — so both str root and arch/common/ need to
# be on the search path. This is the same class of latent issue as the
# `extern` debt tracked in memory for the rest of the tree: harmless until
# something outside lib/str actually tries to assemble it.
nasm -f elf64 -I "$ROOT/lib/str/" -I "$ROOT/lib/str/arch/common/" \
    "$BUILD/root.asm" -o "$BUILD/t.o" || exit 1
ld -no-pie "$BUILD/t.o" -o "$BUILD/t" || exit 1

# The mask arrives as four raw bytes on stdout — see harness.asm in
# security/usrauth/tests for why an exit code would truncate past 8 tests.
MASK=$("$BUILD/t" | od -An -tu4 | tr -d ' ')
RC=${PIPESTATUS[0]}

if [ "$RC" -gt 127 ]; then
    echo "CRASH: signal $((RC - 128))"
    exit 1
fi
if [ -z "$MASK" ]; then
    echo "NO RESULT: the suite exited without reporting (rc=$RC)"
    exit 1
fi

fail=0
chk() {
    if [ $(( MASK & $1 )) -ne 0 ]; then
        echo "  FAIL  $2"
        fail=1
    else
        echo "  pass  $2"
    fi
}

echo "=== dict semantics (mask=$MASK) ==="
chk 1   "T1  word count matches the generated table"
chk 2   "T2  a common word is found"
chk 4   "T3  a non-word is reported NOT_FOUND"
chk 8   "T4  index 0 is the lowest-byte-value entry"
chk 16  "T5  prefix_count(\"zebra\") == 9"
chk 32  "T6  prefix_range(\"zebra\") brackets exactly that run"
chk 64  "T7  suggest(\"wrld\") ranks its five distance-1 neighbors in order"
chk 128 "T8  suggest() with no match reports NOT_FOUND, out_count == 0"
chk 256 "T9  NULL / empty / max_results=0 are rejected as bad arguments"
chk 512  "T10 empty prefix matches the whole dictionary"
chk 1024 "T11 a too-long prefix matches nothing"

echo
if [ "$fail" -eq 0 ]; then
    echo "ALL PASS"
else
    echo "FAILURES PRESENT"
fi
exit "$fail"
