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
    xor eax, eax
    ret

; ============================================================================
; test_inflate_stored (stub)
; ============================================================================
global test_inflate_stored
test_inflate_stored:
    xor eax, eax
    ret

; ============================================================================
; test_adler32_known (stub)
; ============================================================================
global test_adler32_known
test_adler32_known:
    xor eax, eax
    ret

; ============================================================================
; test_png_probe (stub)
; ============================================================================
global test_png_probe
test_png_probe:
    xor eax, eax
    ret

; ============================================================================
; test_png_probe_reject (stub)
; ============================================================================
global test_png_probe_reject
test_png_probe_reject:
    xor eax, eax
    ret

section .data
global test_inflate_version
test_inflate_version: dq 0x010000