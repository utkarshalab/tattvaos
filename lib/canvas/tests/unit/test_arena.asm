; ============================================================================
; Unit Test — Arena Allocator
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"
%include "inc/test.inc"
%include "inc/externs.inc"

section .text

; ============================================================================
; test_arena_main
; ============================================================================
global test_arena_main
test_arena_main:
    PROLOGUE
    xor rax, rax
    ret

; ============================================================================
; TEST_ASSERT_ALIGNED macro (from test.inc)
; ============================================================================
%macro TEST_ASSERT_ALIGNED 2
    ; %1 = value to check, %2 = alignment (power of 2)
    mov rax, %1
    mov rcx, %2
    dec rcx
    test rax, rcx
    jz %%pass
    call test_assert_fail
    jmp %%done
%%pass:
    call test_assert_pass
%%done:
%endmacro

%macro TEST_ASSERT_GE 2
    cmp %1, %2
    jge %%pass
    call test_assert_fail
    jmp %%done
%%pass:
    call test_assert_pass
%%done:
%endmacro

%macro TEST_ASSERT_LE 2
    cmp %1, %2
    jle %%pass
    call test_assert_fail
    jmp %%done
%%pass:
    call test_assert_pass
%%done:
%endmacro

section .data
global test_arena_version
test_arena_version: dq 0x010000