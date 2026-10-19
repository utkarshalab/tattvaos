; ============================================================================
; Unit Test — String Operations
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"
%include "inc/test.inc"
%include "inc/externs.inc"

section .text

; ============================================================================
; test_str_main
; ============================================================================
global test_str_main
test_str_main:
    PROLOGUE
    xor rax, rax
    ret

; ============================================================================
; TEST_ASSERT_LT macro
; ============================================================================
%macro TEST_ASSERT_LT 2
    cmp %1, %2
    jl %%pass
    call test_assert_fail
    jmp %%done
%%pass:
    call test_assert_pass
%%done:
%endmacro

section .data
global test_str_version
test_str_version: dq 0x010000