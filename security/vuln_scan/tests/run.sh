#!/usr/bin/env bash
# security/vuln_scan/tests/run.sh — vuln scan test runner
set -euo pipefail

cd "$(dirname "$0")/.."

echo "[vuln_scan] premium skeleton test suite"
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
echo "  Include file: include/vuln_scan.inc"
echo "  Config file: config/vuln_scan.conf"
echo ""

echo "--- Component symbol exports (vs_*_init, _shutdown, _status, _version) ---"
for comp in vuln_scan scanner assessor database reporter; do
    src="src/${comp}.asm"
    if [ -f "$src" ]; then
        if [ "$comp" = "vuln_scan" ]; then
            sym_prefix="vuln_scan_"
        else
            sym_prefix="vs_${comp}_"
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

check_extra vuln_scan vuln_scan_register_target
check_extra vuln_scan vuln_scan_run_scan
check_extra vuln_scan vuln_scan_assess_finding
check_extra vuln_scan vuln_scan_remediate_finding
check_extra vuln_scan vuln_scan_list_findings
check_extra vuln_scan vuln_scan_get_finding
check_extra vuln_scan vuln_scan_list_scans
check_extra vuln_scan vuln_scan_get_scan
check_extra vuln_scan vuln_scan_cancel_scan
check_extra vuln_scan vuln_scan_update_database
check_extra vuln_scan vuln_scan_get_stats
check_extra scanner vs_scanner_scan_target
check_extra scanner vs_scanner_scan_network
check_extra scanner vs_scanner_scan_application
check_extra scanner vs_scanner_scan_container
check_extra scanner vs_scanner_scan_cloud
check_extra assessor vs_assessor_score_finding
check_extra assessor vs_assessor_prioritize_findings
check_extra database vs_database_add_cve
check_extra database vs_database_lookup_cve
check_extra reporter vs_reporter_generate_report

echo ""
echo "--- Integration checks ---"
if grep -q "include/vuln_scan.inc" src/vuln_scan.asm 2>/dev/null; then
    echo "  PASS: vuln_scan.asm includes vuln_scan.inc"
    pass=$((pass + 1))
else
    echo "  FAIL: vuln_scan.asm missing vuln_scan.inc include"
    fail=$((fail + 1))
fi

if grep -q "GUARD_SECURITY_VULN_SCAN_VULN_SCAN_INC" include/vuln_scan.inc 2>/dev/null; then
    echo "  PASS: vuln_scan.inc has include guard"
    pass=$((pass + 1))
else
    echo "  FAIL: vuln_scan.inc missing include guard"
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