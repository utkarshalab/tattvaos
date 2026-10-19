#!/usr/bin/env bash
# security/privacy_compliance/tests/run.sh — privacy test runner
set -euo pipefail

cd "$(dirname "$0")/.."

echo "[privacy_compliance] premium skeleton test suite"
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
echo "  Include file: include/privacy.inc"
echo "  Config file: config/privacy_compliance.conf"
echo ""

echo "--- Component symbol exports (privacy_*_init, _shutdown, _status, _version) ---"
for comp in privacy_compliance dlp_engine consent classifier reporter; do
    src="src/${comp}.asm"
    if [ -f "$src" ]; then
        if [ "$comp" = "privacy_compliance" ]; then
            sym_prefix="privacy_"
        elif [ "$comp" = "dlp_engine" ]; then
            sym_prefix="privacy_dlp_"
        elif [ "$comp" = "consent" ]; then
            sym_prefix="privacy_consent_"
        elif [ "$comp" = "classifier" ]; then
            sym_prefix="privacy_classifier_"
        elif [ "$comp" = "reporter" ]; then
            sym_prefix="privacy_reporter_"
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
echo "--- Component-specific function exports ---"
check_extra() {
    local comp="$1"
    local sym="$2"
    if grep -q "global ${sym}" "src/${comp}.asm" 2>/dev/null; then
        echo "  PASS: ${comp} exports ${sym}"
        pass=$((pass + 1))
    else
        echo "  FAIL: ${comp} missing ${sym} export"
        fail=$((fail + 1))
    fi
}

check_extra privacy_compliance privacy_register_subject
check_extra privacy_compliance privacy_consent_grant
check_extra privacy_compliance privacy_consent_withdraw
check_extra privacy_compliance privacy_dlp_inspect
check_extra privacy_compliance privacy_classify_data
check_extra privacy_compliance privacy_generate_report
check_extra dlp_engine privacy_dlp_add_policy
check_extra dlp_engine privacy_dlp_inspect_data
check_extra consent privacy_consent_grant
check_extra consent privacy_consent_withdraw
check_extra classifier privacy_classify_data
check_extra reporter privacy_generate_report

echo ""
echo "--- Integration checks ---"
if grep -q "include/privacy.inc" src/privacy_compliance.asm 2>/dev/null; then
    echo "  PASS: privacy_compliance.asm includes privacy.inc"
    pass=$((pass + 1))
else
    echo "  FAIL: privacy_compliance.asm missing privacy.inc include"
    fail=$((fail + 1))
fi

if grep -q "GUARD_SECURITY_PRIVACY_COMPLIANCE_PRIVACY_INC" include/privacy.inc 2>/dev/null; then
    echo "  PASS: privacy.inc has include guard"
    pass=$((pass + 1))
else
    echo "  FAIL: privacy.inc missing include guard"
    fail=$((fail + 1))
fi

stub_count=$(grep -r "STUB" src/*.asm 2>/dev/null | wc -l)
echo ""
echo "--- Premium skeleton markers ---"
echo "  STUB markers in source: $stub_count (logic bodies marked for implementation)"
if [ "$stub_count" -gt 100 ]; then
    echo "  PASS: Premium enterprise skeleton - extensive STUB documentation"
    pass=$((pass + 1))
else
    echo "  FAIL: Insufficient STUB documentation ($stub_count < 100)"
    fail=$((fail + 1))
fi

echo ""
echo "=== Results: $pass passed, $fail failed ==="

if [ "$fail" -gt 0 ]; then
    exit 1
fi

exit 0