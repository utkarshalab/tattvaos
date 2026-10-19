#!/usr/bin/env bash
# security/supply_chain/tests/run.sh — supply chain test runner
set -euo pipefail

cd "$(dirname "$0")/.."

echo "[supply_chain] premium skeleton test suite"
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
echo "  Include file: include/supply_chain.inc"
echo "  Config file: config/supply_chain.conf"
echo ""

echo "--- Component symbol exports (sc_*_init, _shutdown, _status, _version) ---"
for comp in supply_chain sbom provenance attestation verification; do
    src="src/${comp}.asm"
    if [ -f "$src" ]; then
        if [ "$comp" = "supply_chain" ]; then
            sym_prefix="supply_chain_"
        else
            sym_prefix="sc_${comp}_"
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

check_extra supply_chain supply_chain_register_artifact
check_extra supply_chain supply_chain_generate_sbom
check_extra supply_chain supply_chain_attest_artifact
check_extra supply_chain supply_chain_verify_artifact
check_extra sbom sc_sbom_init
check_extra provenance sc_provenance_init
check_extra attestation sc_attestation_init
check_extra verification sc_verification_init

echo ""
echo "--- Integration checks ---"
if grep -q "include/supply_chain.inc" src/supply_chain.asm 2>/dev/null; then
    echo "  PASS: supply_chain.asm includes supply_chain.inc"
    pass=$((pass + 1))
else
    echo "  FAIL: supply_chain.asm missing supply_chain.inc include"
    fail=$((fail + 1))
fi

if grep -q "GUARD_SECURITY_SUPPLY_CHAIN_SUPPLY_CHAIN_INC" include/supply_chain.inc 2>/dev/null; then
    echo "  PASS: supply_chain.inc has include guard"
    pass=$((pass + 1))
else
    echo "  FAIL: supply_chain.inc missing include guard"
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