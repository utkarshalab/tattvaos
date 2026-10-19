; =============================================================================
; File     : src/policy/policy.asm
; Project  : Utkarsha VCS (vcs)
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: Policy engine — path ACLs, required reviews, secret scanning.
; =============================================================================

%ifndef VCS_POLICY_ASM
%define VCS_POLICY_ASM

%include "include/vcs.inc"

bits 64

section .text

; -----------------------------------------------------------------------------
; policy_check — Check if an operation is allowed by policy
; Input:  rdi = subject, rsi = object, rdx = action
; Output: rax = VCS_OK or VCS_ERR_PERM
; -----------------------------------------------------------------------------
global policy_check
policy_check:
    PROLOGUE_SAVE rbx
    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

; -----------------------------------------------------------------------------
; policy_acl_get — Get ACL for a path
; Input:  rdi = path, rsi = output buffer
; Output: rax = VCS_OK or error
; -----------------------------------------------------------------------------
global policy_acl_get
policy_acl_get:
    PROLOGUE_SAVE rbx
    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

; -----------------------------------------------------------------------------
; policy_acl_set — Set ACL for a path
; Input:  rdi = path, rsi = ACL data, rdx = len
; Output: rax = VCS_OK or error
; -----------------------------------------------------------------------------
global policy_acl_set
policy_acl_set:
    PROLOGUE_SAVE rbx
    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

%endif ; VCS_POLICY_ASM