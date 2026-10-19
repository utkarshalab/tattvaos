; ============================================================================
; Fuzz Media — Fuzz Tests for Media Codecs
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"
%include "inc/test.inc"
%include "inc/externs.inc"

section .text

; ============================================================================
; fuzz_target_png (stub)
; ============================================================================
global fuzz_target_png
fuzz_target_png:
    PROLOGUE
    xor rax, rax
    ret

; ============================================================================
; fuzz_target_jpeg (stub)
; ============================================================================
global fuzz_target_jpeg
fuzz_target_jpeg:
    PROLOGUE
    xor rax, rax
    ret

; ============================================================================
; fuzz_target_gif (stub)
; ============================================================================
global fuzz_target_gif
fuzz_target_gif:
    PROLOGUE
    xor rax, rax
    ret

; ============================================================================
; fuzz_target_ttf (stub)
; ============================================================================
global fuzz_target_ttf
fuzz_target_ttf:
    PROLOGUE
    xor rax, rax
    ret

; ============================================================================
; fuzz_target_icc (stub)
; ============================================================================
global fuzz_target_icc
fuzz_target_icc:
    PROLOGUE
    xor rax, rax
    ret

; ============================================================================
; fuzz_target_rfb (stub)
; ============================================================================
global fuzz_target_rfb
fuzz_target_rfb:
    PROLOGUE
    xor rax, rax
    ret

section .data
global fuzz_media_version
fuzz_media_version: dq 0x010000