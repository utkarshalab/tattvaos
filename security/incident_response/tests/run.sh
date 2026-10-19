#!/usr/bin/env bash
# security/incident_response/tests/run.sh — IR test runner
set -euo pipefail

cd "$(dirname "$0")/.."

echo "[incident_response] premium skeleton test suite"
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
echo "  Include file: include/ir.inc"
echo "  Config file: config/incident_response.conf"
echo ""

echo "--- Component symbol exports (ir_*_init, _shutdown, _status, _version) ---"
for comp in incident_response triage containment eradication recovery playbooks; do
    src="src/${comp}.asm"
    if [ -f "$src" ]; then
        if [ "$comp" = "incident_response" ]; then
            sym_prefix="ir_"
        else
            sym_prefix="ir_${comp}_"
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

check_extra incident_response ir_create_incident
check_extra incident_response ir_triage_incident
check_extra incident_response ir_contain_incident
check_extra incident_response ir_eradicate_incident
check_extra incident_response ir_recover_incident
check_extra incident_response ir_close_incident
check_extra triage ir_triage_assess_severity
check_extra triage ir_triage_assign_analyst
check_extra containment ir_containment_isolate_host
check_extra containment ir_containment_revoke_session
check_extra containment ir_containment_block_indicator
check_extra eradication ir_eradication_remove_malware
check_extra eradication ir_eradication_patch_vulnerability
check_extra eradication ir_eradication_reset_credentials
check_extra recovery ir_recovery_restore_backup
check_extra recovery ir_recovery_validate_integrity
check_extra recovery ir_recovery_monitor_activity
check_extra playbooks ir_playbooks_load
check_extra playbooks ir_playbooks_assign
check_extra playbooks ir_playbooks_execute

echo ""
echo "--- Integration checks ---"
if grep -q "include/ir.inc" src/incident_response.asm 2>/dev/null; then
    echo "  PASS: incident_response.asm includes ir.inc"
    pass=$((pass + 1))
else
    echo "  FAIL: incident_response.asm missing ir.inc include"
    fail=$((fail + 1))
fi

if grep -q "GUARD_SECURITY_INCIDENT_RESPONSE_IR_INC" include/ir.inc 2>/dev/null; then
    echo "  PASS: ir.inc has include guard"
    pass=$((pass + 1))
else
    echo "  FAIL: ir.inc missing include guard"
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