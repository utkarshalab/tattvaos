; ============================================================================
; Fuzz Driver — Common Fuzz Testing Infrastructure
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"
%include "inc/test.inc"

section .text

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
