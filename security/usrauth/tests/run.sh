#!/bin/bash
# =============================================================================
# Tattva OS — security/usrauth/tests/run.sh
# =============================================================================
# Builds and runs the usrauth semantic suite as a hosted Linux binary.
#
# The suite exercises the same source the kernel includes; only the two kernel
# services it consumes (the monotonic clock and the entropy pool) are replaced,
# by tests/harness.asm. Nothing inside security/usrauth is stubbed, because a
# suite that tested a stubbed reference monitor would be testing the stub.
#
# Usage:  bash security/usrauth/tests/run.sh
# =============================================================================
set -u

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 1

BUILD=${TMPDIR:-/tmp}/usrauth_test
mkdir -p "$BUILD"

# The include order is the kernel's: primitives, then the monitor that uses
# them. harness.asm goes in before upass so the doubles are defined once.
cat > "$BUILD/root.asm" <<'ASM'
[BITS 64]
%include "crypto/uhash/sha256/sha256.asm"
%include "crypto/ucrypt/mac/hmac.asm"
%include "crypto/ucrypt/guards/ct_guard.asm"
%include "crypto/uhash/sha512/sha512.asm"
%include "crypto/uhash/blake2/blake2b.asm"
%include "security/usrauth/tests/harness.asm"
%include "lib/urand/urand.asm"
%include "crypto/ukdf/pbkdf2/pbkdf2.asm"
%include "crypto/ukdf/argon2/argon2.asm"
%include "crypto/upass/upass.asm"
%include "crypto/usign/ed25519/ed25519.asm"
%include "crypto/usign/ecdsa/ecdsa_p256.asm"
%include "security/usrauth/usrauth.asm"
%include "security/usrauth/tests/usrauth_test.asm"
ASM

nasm -f elf64 -I "$ROOT/" "$BUILD/root.asm" -o "$BUILD/t.o" || exit 1
ld -no-pie "$BUILD/t.o" -o "$BUILD/t" || exit 1

# The mask arrives as four raw bytes on stdout. An exit status would be
# truncated to 8 bits and would lose every test past the eighth.
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

echo "=== usrauth semantics (mask=$MASK) ==="
chk 1      "T1   full stack allows a permitted read"
chk 2      "T2   capability without relation      -> DENY_POLICY"
chk 4      "T3   type enforcement beats cap+rel   -> DENY_MANDATORY"
chk 8      "T4   integrity blocks write-up        -> DENY_INTEGRITY"
chk 16     "T5   delegation cannot amplify (ADMIN dropped)"
chk 32     "T6   delegation keeps the intersected READ"
chk 64     "T7   token issue and verify"
chk 128    "T9   altered token body rejected"
chk 256    "T10  attenuation narrows              -> DENY_CAVEAT"
chk 512    "T11  epoch bump revokes outstanding   -> DENY_REVOKED"
chk 1024   "T12  lapsed relation                  -> DENY_POLICY"
chk 2048   "T13  self-restriction is irreversible -> DENY_CAPABILITY"
chk 4096   "T14  who_can reverse query"
chk 8192   "T15  audit chain intact"
chk 16384  "T16  audit tampering detected"
chk 32768  "T17  MLS no-read-up                   -> DENY_MLS"
chk 65536  "T18  individual revocation            -> DENY_REVOKED"
chk 131072 "T18b sibling token survives revocation"
chk 262144 "T19  forged tag                       -> DENY_FORGED"
chk 524288  "T20  prune reclaims only dead entries"
chk 1048576 "T21  lapsed grant refuses renewal     -> DENY_EXPIRED"
chk 2097152 "T21b refused renewal left deadline alone"
chk 4194304 "T22  live grant renews, clamped to the cap"
chk 8388608 "T23  sweep reaps lapsed, spares renewed"

echo
if [ "$fail" -eq 0 ]; then
    echo "ALL PASS"
else
    echo "FAILURES PRESENT"
fi
exit "$fail"
