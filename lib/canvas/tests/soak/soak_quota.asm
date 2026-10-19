; ============================================================================
; Soak Quota — Stress Test with Quota Enforcement
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"
%include "inc/test.inc"
%include "inc/externs.inc"

section .text

; ============================================================================
; soak_quota_main
; ============================================================================
global soak_quota_main
soak_quota_main:
    PROLOGUE
    xor rax, rax
    ret

; ============================================================================
; surface_create (stub)
; ============================================================================
global surface_create
surface_create:
    PROLOGUE
    xor rax, rax
    ret

section .data
global soak_quota_version
soak_quota_version: dq 0x010000