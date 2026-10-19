#!/usr/bin/env bash
# security/zero_trust/tests/run.sh — Zero Trust premium test runner
set -euo pipefail

cd "$(dirname "$0")/.."

echo "[zero_trust] premium skeleton test suite"
echo ""

pass=0
fail=0

check() {
    local name="$1"
    local result="$2"
    if [ "$result" = "0" ]; then
        echo "  PASS: $name"
        pass=$((pass + 1))
    else
        echo "  FAIL: $name (exit $result)"
        fail=$((fail + 1))
    fi
}

echo "--- Build verification ---"
echo "  Component source files in src/: $(ls -1 src/*.asm | wc -l)"
echo "  Include file: include/zero_trust.inc"
echo "  Config file: config/zero_trust.conf"
echo ""

echo "--- Component symbol exports (zt_*_init, _shutdown, _status, _version) ---"
for comp in zero_trust policy_engine policy_administrator enforcement_point \
            continuous_auth session_manager micro_segmentation posture_checker; do
    src="src/${comp}.asm"
    if [ -f "$src" ]; then
        # zero_trust dispatcher symbols are zt_init, zt_shutdown, etc.
        # policy_administrator symbols are zt_policy_admin_* (not zt_policy_administrator_*)
        if [ "$comp" = "zero_trust" ]; then
            sym_prefix="zt_"
        elif [ "$comp" = "policy_administrator" ]; then
            sym_prefix="zt_policy_admin_"
        else
            sym_prefix="zt_${comp}_"
        fi
        for sym in init shutdown status version; do
            if grep -q "global ${sym_prefix}${sym}" "$src" 2>/dev/null; then
                echo "  PASS: ${comp} exports _${sym}"
                pass=$((pass + 1))
            else
                echo "  FAIL: ${comp} missing _${sym} export"
                fail=$((fail + 1))
            fi
        done
    else
        echo "  FAIL: ${src} not found"
        fail=$((fail + 1))
    fi
done

echo ""
echo "--- Integration checks ---"
if grep -q "../usrauth/include/usrauth.inc" src/zero_trust.asm 2>/dev/null; then
    echo "  PASS: zero_trust.asm includes usrauth.inc (intersection model dependency)"
    pass=$((pass + 1))
else
    echo "  FAIL: zero_trust.asm missing usrauth.inc include"
    fail=$((fail + 1))
fi

if grep -q "include/zero_trust.inc" src/zero_trust.asm 2>/dev/null; then
    echo "  PASS: zero_trust.asm includes zero_trust.inc"
    pass=$((pass + 1))
else
    echo "  FAIL: zero_trust.asm missing zero_trust.inc include"
    fail=$((fail + 1))
fi

if grep -q "GUARD_SECURITY_ZERO_TRUST_INC_ZERO_TRUST_INC" include/zero_trust.inc 2>/dev/null; then
    echo "  PASS: zero_trust.inc has include guard"
    pass=$((pass + 1))
else
    echo "  FAIL: zero_trust.inc missing include guard"
    fail=$((fail + 1))
fi

# Verify all components have STUB markers (premium skeleton marker)
stub_count=$(grep -r "STUB" src/*.asm 2>/dev/null | wc -l)
echo ""
echo "--- Premium skeleton markers ---"
echo "  STUB markers in source: $stub_count (logic bodies marked for implementation)"
if [ "$stub_count" -gt 20 ]; then
    echo "  PASS: Premium skeleton - extensive STUB documentation"
    pass=$((pass + 1))
else
    echo "  FAIL: Insufficient STUB documentation"
    fail=$((fail + 1))
fi

echo ""
echo "=== Results: $pass passed, $fail failed ==="

if [ "$fail" -gt 0 ]; then
    exit 1
fi

exit 0
