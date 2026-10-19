; ============================================================================
; Fuzz Driver — Common Fuzz Testing Infrastructure
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"
%include "inc/test.inc"
%include "inc/externs.inc"

section .text

; ============================================================================
; wire_validate_message (stub)
; ============================================================================
global wire_validate_message
wire_validate_message:
    PROLOGUE
    xor rax, rax
    ret

; ============================================================================
; wire_decode_header (stub)
; ============================================================================
global wire_decode_header
wire_decode_header:
    PROLOGUE
    xor rax, rax
    ret

; ============================================================================
; wire_decode_handles (stub)
; ============================================================================
global wire_decode_handles
wire_decode_handles:
    PROLOGUE
    xor rax, rax
    ret

; ============================================================================
; gif_probe (stub)
; ============================================================================
global gif_probe
gif_probe:
    PROLOGUE
    xor rax, rax
    ret

; ============================================================================
; fuzz_driver_main
; ============================================================================
global fuzz_driver_main
fuzz_driver_main:
    PROLOGUE
    xor rax, rax
    ret

section .data
global fuzz_driver_version
fuzz_driver_version: dq 0x010000