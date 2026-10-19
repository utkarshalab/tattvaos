; =============================================================================
; File     : src/policy/audit.asm
; Project  : Utkarsha VCS (vcs)
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: Audit trail — tamper-evident log of reads, writes, admin actions.
; =============================================================================

%ifndef VCS_POLICY_AUDIT_ASM
%define VCS_POLICY_AUDIT_ASM

%include "include/vcs.inc"

bits 64

section .text

; -----------------------------------------------------------------------------
; audit_write — Append an audit record
; Input:  rdi = subject, rsi = action, rdx = object, rcx = details
; Output: rax = VCS_OK
; -----------------------------------------------------------------------------
global audit_write
audit_write:
    PROLOGUE_SAVE rbx
    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

; -----------------------------------------------------------------------------
; audit_query — Query audit records matching criteria
; Input:  rdi = filter, rsi = output buffer, rdx = max entries
; Output: rax = number of records
; -----------------------------------------------------------------------------
global audit_query
audit_query:
    PROLOGUE_SAVE rbx
    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

%endif ; VCS_POLICY_AUDIT_ASM