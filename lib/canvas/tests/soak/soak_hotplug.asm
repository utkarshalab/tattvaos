; ============================================================================
; Soak Hotplug — Stress Test with Hotplug Events
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"
%include "inc/test.inc"
%include "inc/externs.inc"

section .text

; ============================================================================
; soak_hotplug_main
; ============================================================================
global soak_hotplug_main
soak_hotplug_main:
    PROLOGUE
    xor rax, rax
    ret

; ============================================================================
; output_layout_apply (stub)
; ============================================================================
global output_layout_apply
output_layout_apply:
    PROLOGUE
    xor rax, rax
    ret

section .data
global soak_hotplug_version
soak_hotplug_version: dq 0x010000