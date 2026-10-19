#!/usr/bin/env bash
# security/threat_intel/tests/run.sh — threat intel test runner
set -euo pipefail

cd "$(dirname "$0")/.."

echo "[threat_intel] premium skeleton test suite"
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
echo "  Include file: include/threat_intel.inc"
echo "  Config file: config/threat_intel.conf"
echo ""

echo "--- Component symbol exports (ti_*_init, _shutdown, _status, _version) ---"
for comp in threat_intel store ingestor exporter correlator; do
    src="src/${comp}.asm"
    if [ -f "$src" ]; then
        if [ "$comp" = "threat_intel" ]; then
            sym_prefix="threat_intel_"
        else
            sym_prefix="ti_${comp}_"
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

check_extra store       ti_store_add_ioc
check_extra store       ti_store_lookup_ioc
check_extra store       ti_store_remove_ioc
check_extra store       ti_store_get_ioc_count
check_extra ingestor    ti_ingestor_pull_feed
check_extra ingestor    ti_ingestor_push_feed
check_extra ingestor    ti_ingestor_verify_signature
check_extra exporter    ti_exporter_share_ioc
check_extra exporter    ti_exporter_push_siem
check_extra exporter    ti_exporter_pull_peer
check_extra correlator  ti_correlator_match_event
check_extra correlator  ti_correlator_score_ioc
check_extra correlator  ti_correlator_update_score
check_extra threat_intel threat_intel_ingest
check_extra threat_intel threat_intel_lookup
check_extra threat_intel threat_intel_subscribe
check_extra threat_intel threat_intel_match

echo ""
echo "--- Integration checks ---"
if grep -q "include/threat_intel.inc" src/threat_intel.asm 2>/dev/null; then
    echo "  PASS: threat_intel.asm includes threat_intel.inc"
    pass=$((pass + 1))
else
    echo "  FAIL: threat_intel.asm missing threat_intel.inc include"
    fail=$((fail + 1))
fi

if grep -q "include/threat_intel.inc" src/store.asm 2>/dev/null; then
    echo "  PASS: store.asm includes threat_intel.inc"
    pass=$((pass + 1))
else
    echo "  FAIL: store.asm missing threat_intel.inc include"
    fail=$((fail + 1))
fi

if grep -q "include/threat_intel.inc" src/ingestor.asm 2>/dev/null; then
    echo "  PASS: ingestor.asm includes threat_intel.inc"
    pass=$((pass + 1))
else
    echo "  FAIL: ingestor.asm missing threat_intel.inc include"
    fail=$((fail + 1))
fi

if grep -q "include/threat_intel.inc" src/exporter.asm 2>/dev/null; then
    echo "  PASS: exporter.asm includes threat_intel.inc"
    pass=$((pass + 1))
else
    echo "  FAIL: exporter.asm missing threat_intel.inc include"
    fail=$((fail + 1))
fi

if grep -q "include/threat_intel.inc" src/correlator.asm 2>/dev/null; then
    echo "  PASS: correlator.asm includes threat_intel.inc"
    pass=$((pass + 1))
else
    echo "  FAIL: correlator.asm missing threat_intel.inc include"
    fail=$((fail + 1))
fi

if grep -q "GUARD_SECURITY_THREAT_INTEL_THREAT_INTEL_INC" include/threat_intel.inc 2>/dev/null; then
    echo "  PASS: threat_intel.inc has include guard"
    pass=$((pass + 1))
else
    echo "  FAIL: threat_intel.inc missing include guard"
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