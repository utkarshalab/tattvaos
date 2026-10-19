; =============================================================================
; File     : src/policy/transparency.asm
; Project  : Utkarsha VCS (vcs)
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: Transparency log — Merkle tree of ref updates for integrity.
; =============================================================================

%ifndef VCS_POLICY_TRANSPARENCY_ASM
%define VCS_POLICY_TRANSPARENCY_ASM

%include "include/vcs.inc"

bits 64

section .text

; -----------------------------------------------------------------------------
; transparency_append — Append a ref update to the transparency log
; Input:  rdi = ref name, rsi = old hash, rdx = new hash
; Output: rax = log entry index or error
; -----------------------------------------------------------------------------
global transparency_append
transparency_append:
    PROLOGUE_SAVE rbx
    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

; -----------------------------------------------------------------------------
; transparency_verify — Verify consistency proof between two log points
; Input:  rdi = first index, rsi = second index, rdx = proof buffer
; Output: rax = VCS_OK or error
; -----------------------------------------------------------------------------
global transparency_verify
transparency_verify:
    PROLOGUE_SAVE rbx
    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

%endif ; VCS_POLICY_TRANSPARENCY_ASM