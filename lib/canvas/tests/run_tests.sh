#!/bin/bash
# ============================================================================
# Canvas Test Runner — Build and Run Tests on Utkarsha
# ============================================================================

set -euo pipefail

CANVAS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$CANVAS_ROOT/build"
TEST_IMG="$BUILD_DIR/img/test_runner.img"

echo "=== Canvas Test Runner ==="
echo "Canvas root: $CANVAS_ROOT"
echo "Build dir:   $BUILD_DIR"

# Build test runner
echo "Building test runner..."
cd "$CANVAS_ROOT"
make clean
make test

if [[ ! -f "$TEST_IMG" ]]; then
    echo "ERROR: Test image not found at $TEST_IMG"
    exit 1
fi

echo "Test image: $TEST_IMG ($(stat -c%s "$TEST_IMG") bytes)"

# Run on Utkarsha (this would be replaced with actual Utkarsha execution)
echo ""
echo "To run on Utkarsha:"
echo "  1. Copy $TEST_IMG to Utkarsha boot media"
echo "  2. Boot Utkarsha with test_runner.img as init"
echo "  3. Collect serial output for results"
echo ""
echo "Expected serial output format:"
echo "  === TEST SUITE: test_arena_suite ==="
echo "  TEST: test_arena_init"
echo "    PASS: test_arena_init"
echo "  DONE"
echo "  ..."
echo "  === SUMMARY: total=14 passed=14 failed=0 ==="

# If running in QEMU with Utkarsha (for CI)
if [[ "${UT_QEMU:-}" == "1" ]]; then
    echo "Running in QEMU..."
    qemu-system-x86_64 \
        -kernel /path/to/utkarsha/kernel \
        -initrd "$TEST_IMG" \
        -nographic \
        -serial stdio \
        -no-reboot
fi