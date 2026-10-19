#!/usr/bin/env bash
# security/ids/tests/run.sh — IDS premium test runner
set -euo pipefail

cd "$(dirname "$0")/.."

echo "[ids] premium skeleton test suite"
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
echo "  Include file: include/ids.inc"
echo "  Config file: config/ids.conf"
echo ""

echo "--- Component symbol exports (ids_*_init, _shutdown, _status, _version) ---"
for comp in ids sensor reassembler analyzer rules detector alert correlator siem stats; do
    src="src/${comp}.asm"
    if [ -f "$src" ]; then
        # ids dispatcher symbols are ids_init, ids_shutdown, etc.
        # (not ids_ids_init)
        if [ "$comp" = "ids" ]; then
            sym_prefix="ids_"
        else
            sym_prefix="ids_${comp}_"
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

# Component-specific function exports
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

check_extra sensor       ids_sensor_capture
check_extra reassembler  ids_reassembler_add_packet
check_extra analyzer     ids_analyzer_parse
check_extra rules        ids_rules_load
check_extra rules        ids_rules_match
check_extra detector     ids_detector_evaluate
check_extra alert        ids_alert_emit
check_extra alert        ids_alert_acknowledge
check_extra correlator   ids_correlator_update
check_extra siem         ids_siem_export
check_extra stats        ids_stats_record

echo ""
echo "--- Integration checks ---"
if grep -q "include/ids.inc" src/ids.asm 2>/dev/null; then
    echo "  PASS: ids.asm includes ids.inc"
    pass=$((pass + 1))
else
    echo "  FAIL: ids.asm missing ids.inc include"
    fail=$((fail + 1))
fi

if grep -q "GUARD_SECURITY_IDS_INC_IDS_INC" include/ids.inc 2>/dev/null; then
    echo "  PASS: ids.inc has include guard"
    pass=$((pass + 1))
else
    echo "  FAIL: ids.inc missing include guard"
    fail=$((fail + 1))
fi

# Verify all components have STUB markers (premium skeleton marker)
stub_count=$(grep -r "STUB" src/*.asm 2>/dev/null | wc -l)
echo ""
echo "--- Premium skeleton markers ---"
echo "  STUB markers in source: $stub_count (logic bodies marked for implementation)"
if [ "$stub_count" -gt 50 ]; then
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
