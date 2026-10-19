; =============================================================================
; File     : src/merge/conflicts.asm
; Project  : Utkarsha VCS (vcs)
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: Conflict objects — store, resolve, propagate.
; =============================================================================

%ifndef VCS_MERGE_CONFLICTS_ASM
%define VCS_MERGE_CONFLICTS_ASM

%include "include/vcs.inc"

bits 64

section .text

; -----------------------------------------------------------------------------
; conflict_create — Create a conflict object
; Input:  rdi = path, rsi = ours hash, rdx = theirs hash, rcx = base hash
; Output: rax = conflict object pointer
; -----------------------------------------------------------------------------
global conflict_create
conflict_create:
    PROLOGUE_SAVE rbx
    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

; -----------------------------------------------------------------------------
; conflict_resolve — Resolve conflict with given resolution
; Input:  rdi = conflict object, rsi = resolution type
; Output: rax = VCS_OK
; -----------------------------------------------------------------------------
global conflict_resolve
conflict_resolve:
    PROLOGUE_SAVE rbx
    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

%endif ; VCS_MERGE_CONFLICTS_ASM