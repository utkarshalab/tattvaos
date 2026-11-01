; ============================================================================
; Unit Test — Region
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"
%include "inc/test.inc"
%include "inc/externs.inc"

section .text

; ============================================================================
; test_region_main
; ============================================================================
global test_region_main
test_region_main:
    xor eax, eax
    ret

; ============================================================================
; test_region_init (stub)
; ============================================================================
global test_region_init
test_region_init:
    xor eax, eax
    ret

; ============================================================================
; test_region_add_rect (stub)
; ============================================================================
global test_region_add_rect
test_region_add_rect:
    xor eax, eax
    ret

section .data
global test_region_version
test_region_version: dq 0x010000