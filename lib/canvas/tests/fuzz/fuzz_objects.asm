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
; fuzz_target_objects (stub)
; ============================================================================
global fuzz_target_objects
fuzz_target_objects:
    xor eax, eax
    ret

section .data
global fuzz_objects_version
fuzz_objects_version: dq 0x010000