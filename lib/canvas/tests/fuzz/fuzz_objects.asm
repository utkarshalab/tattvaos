; ============================================================================
; Fuzz Objects — Fuzz Tests for Protocol Objects
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"
%include "inc/test.inc"
%include "inc/externs.inc"

section .text

; ============================================================================
; fuzz_target_wire (stub)
; ============================================================================
global fuzz_target_wire
fuzz_target_wire:
    PROLOGUE
    xor rax, rax
    ret

; ============================================================================
; handle_resolve (stub)
; ============================================================================
global handle_resolve
handle_resolve:
    PROLOGUE
    xor rax, rax
    ret

section .data
global fuzz_objects_version
fuzz_objects_version: dq 0x010000