; ============================================================================
; Soak Churn — Stress Test with Churn
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"
%include "inc/test.inc"
%include "inc/externs.inc"

section .text

; ============================================================================
; soak_churn_main
; ============================================================================
global soak_churn_main
soak_churn_main:
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

; ============================================================================
; commit_surface (stub)
; ============================================================================
global commit_surface
commit_surface:
    PROLOGUE
    xor rax, rax
    ret

section .data
global soak_churn_version
soak_churn_version: dq 0x010000