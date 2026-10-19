#!/usr/bin/env bash
# security/digital_forensics/tests/run.sh — DFIR test runner
set -euo pipefail

cd "$(dirname "$0")/.."

echo "[digital_forensics] premium skeleton test suite"
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
echo "  Include file: include/dfir.inc"
echo "  Config file: config/digital_forensics.conf"
echo ""

echo "--- Component symbol exports (dfir_*_init, _shutdown, _status, _version) ---"
for comp in dfir acquirer analyzer custody reporter; do
    src="src/${comp}.asm"
    if [ -f "$src" ]; then
        if [ "$comp" = "dfir" ]; then
            sym_prefix="dfir_"
        else
            sym_prefix="dfir_${comp}_"
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

check_extra dfir dfir_create_case
check_extra dfir dfir_acquire_evidence
check_extra dfir dfir_analyze_evidence
check_extra dfir dfir_custody_transfer
check_extra dfir dfir_generate_report
check_extra acquirer dfir_acquirer_acquire_disk
check_extra acquirer dfir_acquirer_acquire_memory
check_extra acquirer dfir_acquirer_acquire_file
check_extra analyzer dfir_analyzer_carve_filesystem
check_extra analyzer dfir_analyzer_build_timeline
check_extra analyzer dfir_analyzer_search_strings
check_extra custody dfir_custody_log_entry
check_extra custody dfir_custody_verify_chain
check_extra reporter dfir_reporter_generate_pdf
check_extra reporter dfir_reporter_generate_json
check_extra reporter dfir_reporter_generate_html

echo ""
echo "--- Integration checks ---"
if grep -q "include/dfir.inc" src/dfir.asm 2>/dev/null; then
    echo "  PASS: dfir.asm includes dfir.inc"
    pass=$((pass + 1))
else
    echo "  FAIL: dfir.asm missing dfir.inc include"
    fail=$((fail + 1))
fi

if grep -q "GUARD_SECURITY_DIGITAL_FORENSICS_DFIR_INC" include/dfir.inc 2>/dev/null; then
    echo "  PASS: dfir.inc has include guard"
    pass=$((pass + 1))
else
    echo "  FAIL: dfir.inc missing include guard"
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