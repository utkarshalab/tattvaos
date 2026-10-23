; ============================================================================
; Unit Test — TTF Font Parser
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"
%include "inc/test.inc"
%include "inc/externs.inc"

section .text

; ============================================================================
; test_ttf_main
; ============================================================================
global test_ttf_main
test_ttf_main:
    PROLOGUE
    xor rax, rax
    ret

; ============================================================================
; test_ttf_probe_truetype (stub)
; ============================================================================
global test_ttf_probe_truetype
test_ttf_probe_truetype:
    PROLOGUE
    xor rax, rax
    ret

; ============================================================================
; test_ttf_probe_otf (stub)
; ============================================================================
global test_ttf_probe_otf
test_ttf_probe_otf:
    PROLOGUE
    xor rax, rax
    ret

; ============================================================================
; test_ttf_probe_reject (stub)
; ============================================================================
global test_ttf_probe_reject
test_ttf_probe_reject:
    PROLOGUE
    xor rax, rax
    ret

; ============================================================================
; test_ttf_be16 (stub)
; ============================================================================
global test_ttf_be16
test_ttf_be16:
    PROLOGUE
    xor rax, rax
    ret

; ============================================================================
; test_ttf_be32 (stub)
; ============================================================================
global test_ttf_be32
test_ttf_be32:
    PROLOGUE
    xor rax, rax
    ret

section .data
global test_ttf_version
test_ttf_version: dq 0x010000