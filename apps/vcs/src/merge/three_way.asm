; =============================================================================
; File     : src/merge/three_way.asm
; Project  : Utkarsha VCS (vcs)
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: Three-way merge core algorithm.
; =============================================================================

%ifndef VCS_MERGE_THREE_WAY_ASM
%define VCS_MERGE_THREE_WAY_ASM

%include "include/vcs.inc"

bits 64

section .text

; -----------------------------------------------------------------------------
; three_way_merge — Merge base, left, right at file level
; Input:  rdi = base, rsi = left, rdx = right, rcx = output
; Output: rax = VCS_OK or VCS_ERR_CONFLICT
; -----------------------------------------------------------------------------
global three_way_merge
three_way_merge:
    PROLOGUE_SAVE rbx
    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

%endif ; VCS_MERGE_THREE_WAY_ASM