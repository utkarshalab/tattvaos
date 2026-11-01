; ============================================================================
; Fuzz Media — Fuzz Tests for Media Codecs
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"
%include "inc/test.inc"
%include "inc/externs.inc"

section .text

; ============================================================================
; fuzz_target_png (stub)
; ============================================================================
global fuzz_target_png
fuzz_target_png:
    xor eax, eax
    ret

; ============================================================================
; fuzz_target_jpeg (stub)
; ============================================================================
global fuzz_target_jpeg
fuzz_target_jpeg:
    xor eax, eax
    ret

; ============================================================================
; fuzz_target_gif (stub)
; ============================================================================
global fuzz_target_gif
fuzz_target_gif:
    xor eax, eax
    ret

; ============================================================================
; fuzz_target_ttf (stub)
; ============================================================================
global fuzz_target_ttf
fuzz_target_ttf:
    xor eax, eax
    ret

; ============================================================================
; fuzz_target_icc (stub)
; ============================================================================
global fuzz_target_icc
fuzz_target_icc:
    xor eax, eax
    ret

; ============================================================================
; fuzz_target_rfb (stub)
; ============================================================================
global fuzz_target_rfb
fuzz_target_rfb:
    xor eax, eax
    ret

section .data
global fuzz_media_version
fuzz_media_version: dq 0x010000