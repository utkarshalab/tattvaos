; =============================================================================
; File     : src/policy/acls.asm
; Project  : Utkarsha VCS (vcs)
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: Path-level access control lists.
; =============================================================================

%ifndef VCS_POLICY_ACLS_ASM
%define VCS_POLICY_ACLS_ASM

%include "include/vcs.inc"

bits 64

section .text

; -----------------------------------------------------------------------------
; acl_evaluate — Evaluate ACL for subject on path
; Input:  rdi = subject, rsi = path, rdx = action
; Output: rax = 1 if allowed, 0 if denied
; -----------------------------------------------------------------------------
global acl_evaluate
acl_evaluate:
    PROLOGUE_SAVE rbx
    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

%endif ; VCS_POLICY_ACLS_ASM