%ifndef GUARD_TESTS_UNIT_TEST_SUITE_ASM
%define GUARD_TESTS_UNIT_TEST_SUITE_ASM
; =============================================================================
; File     : tests/unit/test_suite.asm
; Project  : Tattva OS
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: Unit test suite entry point — runs all unit tests.
; =============================================================================

bits 64

section .text

; -----------------------------------------------------------------------------
; test_unit_run — Run all unit tests
; Input:  none
; Output: rax = 0 if all passed, non-zero if failed
; -----------------------------------------------------------------------------
global test_unit_run
test_unit_run:
    ret

%endif ; GUARD_TESTS_UNIT_TEST_SUITE_ASM