; ============================================================================
; Unit Test — Inflate/Deflate
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"
%include "inc/test.inc"
%include "inc/externs.inc"

section .text

; ============================================================================
; test_inflate_main
; ============================================================================
global test_inflate_main
test_inflate_main:
    PROLOGUE
    xor rax, rax
    ret

; ============================================================================
; test_inflate_stored (stub)
; ============================================================================
global test_inflate_stored
test_inflate_stored:
    PROLOGUE
    xor rax, rax
    ret

; ============================================================================
; arena_init (stub)
; ============================================================================
global arena_init
arena_init:
    PROLOGUE
    xor rax, rax
    ret

; ============================================================================
; test_adler32_known (stub)
; ============================================================================
global test_adler32_known
test_adler32_known:
    PROLOGUE
    xor rax, rax
    ret

; ============================================================================
; test_png_probe (stub)
; ============================================================================
global test_png_probe
test_png_probe:
    PROLOGUE
    xor rax, rax
    ret

; ============================================================================
; test_png_probe_reject (stub)
; ============================================================================
global test_png_probe_reject
test_png_probe_reject:
    PROLOGUE
    xor rax, rax
    ret

section .data
global test_inflate_version
test_inflate_version: dq 0x010000