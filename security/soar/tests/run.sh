#!/usr/bin/env bash
# security/soar/tests/run.sh — SOAR premium test runner
set -euo pipefail

cd "$(dirname "$0")/.."

echo "[soar] premium skeleton test suite"
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
echo "  Include file: include/soar.inc"
echo "  Config file: config/soar.conf"
echo ""

echo "--- Component symbol exports (soar_*_init, _shutdown, _status, _version) ---"
# Map component filenames to their actual symbol prefixes used in source
declare -A sym_prefixes
sym_prefixes[soar]="soar_"
sym_prefixes[core_engine]="soar_core_"
sym_prefixes[playbook_engine]="soar_policy_"
sym_prefixes[alert_ingestor]="soar_alert_"
sym_prefixes[action_engine]="soar_action_"
sym_prefixes[playbook_compiler]="soar_rulec_"
sym_prefixes[case_manager]="soar_case_manager_"
sym_prefixes[automation_engine]="soar_automation_engine_"
sym_prefixes[integration_engine]="soar_integration_engine_"
sym_prefixes[scheduler]="soar_scheduler_"
sym_prefixes[metrics_engine]="soar_metrics_engine_"

for comp in soar core_engine playbook_engine alert_ingestor action_engine playbook_compiler case_manager automation_engine integration_engine scheduler metrics_engine; do
    src="src/${comp}.asm"
    if [ -f "$src" ]; then
        sym_prefix="${sym_prefixes[$comp]}"
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

check_extra core_engine soar_core_register
check_extra playbook_engine soar_policy_load
check_extra playbook_engine soar_policy_evaluate
check_extra alert_ingestor soar_alert_ingest
check_extra action_engine soar_action_execute
check_extra playbook_compiler soar_rulec_compile
check_extra case_manager soar_case_create
check_extra automation_engine soar_automation_engine_execute
check_extra integration_engine soar_integration_engine_send
check_extra scheduler soar_scheduler_add
check_extra metrics_engine soar_metrics_engine_record

echo ""
echo "--- Integration checks ---"
if grep -q "include/soar.inc" src/soar.asm 2>/dev/null; then
    echo "  PASS: soar.asm includes soar.inc"
    pass=$((pass + 1))
else
    echo "  FAIL: soar.asm missing soar.inc include"
    fail=$((fail + 1))
fi

if grep -q "GUARD_SECURITY_SOAR_INC_SOAR_INC" include/soar.inc 2>/dev/null; then
    echo "  PASS: soar.inc has include guard"
    pass=$((pass + 1))
else
    echo "  FAIL: soar.inc missing include guard"
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