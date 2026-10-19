; ============================================================================
; Unit Test — RFB Protocol
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"
%include "inc/test.inc"
%include "inc/externs.inc"

section .text

; ============================================================================
; test_rfb_main
; ============================================================================
global test_rfb_main
test_rfb_main:
    PROLOGUE
    xor rax, rax
    ret

; ============================================================================
; test_rfb_version_check (stub)
; ============================================================================
global test_rfb_version_check
test_rfb_version_check:
    PROLOGUE
    xor rax, rax
    ret

; ============================================================================
; test_rfb_version_reject (stub)
; ============================================================================
global test_rfb_version_reject
test_rfb_version_reject:
    PROLOGUE
    xor rax, rax
    ret

section .data
global test_rfb_version
test_rfb_version: dq 0x010000