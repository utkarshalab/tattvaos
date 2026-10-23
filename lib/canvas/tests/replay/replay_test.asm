; ============================================================================
; Replay Test — Deterministic Replay Testing
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"
%include "inc/test.inc"
%include "inc/externs.inc"

section .text

; ============================================================================
; replay_test_main
; ============================================================================
global replay_test_main
replay_test_main:
    PROLOGUE
    xor rax, rax
    ret

section .data
global replay_test_version
replay_test_version: dq 0x010000