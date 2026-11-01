; ============================================================================
; Unit Test — ICC Profile Parser
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"
%include "inc/test.inc"
%include "inc/externs.inc"

section .text

; ============================================================================
; test_icc_main
; ============================================================================
global test_icc_main
test_icc_main:
    xor eax, eax
    ret

; ============================================================================
; test_icc_probe_reject (stub)
; ============================================================================
global test_icc_probe_reject
test_icc_probe_reject:
    xor eax, eax
    ret

; ============================================================================
; test_icc_probe_magic (stub)
; ============================================================================
global test_icc_probe_magic
test_icc_probe_magic:
    xor eax, eax
    ret

; ============================================================================
; test_mat3_identity (stub)
; ============================================================================
global test_mat3_identity
test_mat3_identity:
    xor eax, eax
    ret

; ============================================================================
; test_trc (stub)
; ============================================================================
global test_trc
test_trc:
    xor eax, eax
    ret

section .data
global test_icc_version
test_icc_version: dq 0x010000