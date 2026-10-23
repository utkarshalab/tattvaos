; ============================================================================
; Unit Test — Ring Buffer
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"
%include "inc/test.inc"
%include "inc/externs.inc"

section .text

; ============================================================================
; test_ring_main
; ============================================================================
global test_ring_main
test_ring_main:
    PROLOGUE
    xor rax, rax
    ret

; ============================================================================
; test_ring_basic (stub)
; ============================================================================
global test_ring_basic
test_ring_basic:
    PROLOGUE
    xor rax, rax
    ret

section .data
global test_ring_version
test_ring_version: dq 0x010000