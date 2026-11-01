; ============================================================================
; Unit Test — Map/Hash Table
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"
%include "inc/test.inc"
%include "inc/externs.inc"

section .text

; ============================================================================
; test_map_main
; ============================================================================
global test_map_main
test_map_main:
    xor eax, eax
    ret

; ============================================================================
; test_map_init (stub)
; ============================================================================
global test_map_init
test_map_init:
    xor eax, eax
    ret

; ============================================================================
; test_map_put_get (stub)
; ============================================================================
global test_map_put_get
test_map_put_get:
    xor eax, eax
    ret

section .data
global test_map_version
test_map_version: dq 0x010000