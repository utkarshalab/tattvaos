; ============================================================================
; Unit Test — Map/Hash Table
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"
%include "inc/test.inc"
%include "inc/externs.inc"

section .text

; ============================================================================
; test_map_main
; ============================================================================
global test_map_main
test_map_main:
    PROLOGUE
    xor rax, rax
    ret

; ============================================================================
; test_map_init (stub)
; ============================================================================
global test_map_init
test_map_init:
    PROLOGUE
    xor rax, rax
    ret

; ============================================================================
; test_map_put_get (stub)
; ============================================================================
global test_map_put_get
test_map_put_get:
    PROLOGUE
    xor rax, rax
    ret

section .data
global test_map_version
test_map_version: dq 0x010000