; ============================================================================
; Fuzz Keymap Config — Fuzz Test for Keymap Configuration
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"
%include "inc/test.inc"
%include "inc/externs.inc"

section .text

; ============================================================================
; fuzz_target_keymap (stub)
; ============================================================================
global fuzz_target_keymap
fuzz_target_keymap:
    PROLOGUE
    xor rax, rax
    ret

; ============================================================================
; fuzz_target_config (stub)
; ============================================================================
global fuzz_target_config
fuzz_target_config:
    PROLOGUE
    xor rax, rax
    ret

section .data
global fuzz_keymap_config_version
fuzz_keymap_config_version: dq 0x010000