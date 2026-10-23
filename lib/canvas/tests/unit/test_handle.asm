; ============================================================================
; Unit Test — Handle Allocator
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"
%include "inc/test.inc"
%include "inc/externs.inc"

section .text

; ============================================================================
; test_handle_main
; ============================================================================
global test_handle_main
test_handle_main:
    PROLOGUE
    xor rax, rax
    ret

; ============================================================================
; test_handle_basic (stub)
; ============================================================================
global test_handle_basic
test_handle_basic:
    PROLOGUE
    xor rax, rax
    ret

section .data
global test_handle_version
test_handle_version: dq 0x010000