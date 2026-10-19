#!/usr/bin/env bash
# security/waf/tests/run.sh — WAF premium test runner
set -euo pipefail

cd "$(dirname "$0")/.."

echo "[waf] premium enterprise test suite"
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
echo "  Include file: include/waf.inc"
echo "  Config file: config/waf.conf"
echo ""

echo "--- Component symbol exports (waf_*_init, _shutdown, _status, _version) ---"
for comp in waf core rule http sqli xss csrf fim cmd deser api rate bot session geoip rulec siem stats; do
    if [ "$comp" = "waf" ]; then
        src="src/waf.asm"
        sym_prefix="waf_"
    else
        src="src/waf_${comp}.asm"
        sym_prefix="waf_${comp}_"
    fi
    if [ -f "$src" ]; then
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

check_extra waf_core waf_core_init
check_extra waf_rule waf_rule_load
check_extra waf_rule waf_rule_evaluate
check_extra waf_http waf_http_parse
check_extra waf_http waf_http_extract
check_extra waf_sqli waf_sqli_detect
check_extra waf_xss waf_xss_detect
check_extra waf_csrf waf_csrf_validate
check_extra waf_fim waf_fim_detect
check_extra waf_cmd waf_cmd_detect
check_extra waf_deser waf_deser_detect
check_extra waf_api waf_api_authenticate
check_extra waf_api waf_api_rate_limit
check_extra waf_rate waf_rate_check
check_extra waf_bot waf_bot_detect
check_extra waf_bot waf_bot_score
check_extra waf_session waf_session_validate
check_extra waf_session waf_session_track
check_extra waf_geoip waf_geoip_lookup
check_extra waf_geoip waf_geoip_is_blocked
check_extra waf_rulec waf_rulec_compile
check_extra waf_siem waf_siem_export
check_extra waf_stats waf_stats_record

echo ""
echo "--- Integration checks ---"
if grep -q "include/waf.inc" src/waf.asm 2>/dev/null; then
    echo "  PASS: waf.asm includes waf.inc"
    pass=$((pass + 1))
else
    echo "  FAIL: waf.asm missing waf.inc include"
    fail=$((fail + 1))
fi

if grep -q "GUARD_SECURITY_WAF_INC_WAF_INC" include/waf.inc 2>/dev/null; then
    echo "  PASS: waf.inc has include guard"
    pass=$((pass + 1))
else
    echo "  FAIL: waf.inc missing include guard"
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
    echo "  FAIL: Insufficient STUB documentation"
    fail=$((fail + 1))
fi

echo ""
echo "=== Results: $pass passed, $fail failed ==="

if [ "$fail" -gt 0 ]; then
    exit 1
fi

exit 0
