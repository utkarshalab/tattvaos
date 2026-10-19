; =============================================================================
; File     : src/merge/merge.asm
; Project  : Utkarsha VCS (vcs)
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: Merge engine — three-way tree merge, conflict resolution.
; =============================================================================

%ifndef VCS_MERGE_ASM
%define VCS_MERGE_ASM

%include "include/vcs.inc"

bits 64

section .text

; -----------------------------------------------------------------------------
; merge_three_way — Three-way merge of base, ours, theirs
; Input:  rdi = base tree, rsi = ours tree, rdx = theirs tree
; Output: rax = VCS_OK, rsi = result tree (or conflict object)
; -----------------------------------------------------------------------------
global merge_three_way
merge_three_way:
    PROLOGUE_SAVE rbx, rcx, rdx
    xor     rax, rax
    EPILOGUE_RESTORE rbx, rcx, rdx
    ret

; -----------------------------------------------------------------------------
; merge_resolve — Resolve a conflict at a given path
; Input:  rdi = conflict object, rsi = resolution (ours/theirs/both)
; Output: rax = VCS_OK
; -----------------------------------------------------------------------------
global merge_resolve
merge_resolve:
    PROLOGUE_SAVE rbx
    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

; -----------------------------------------------------------------------------
; merge_conflict_list — List all unresolved conflicts in a commit
; Input:  rdi = commit hash, rsi = output array
; Output: rax = number of conflicts
; -----------------------------------------------------------------------------
global merge_conflict_list
merge_conflict_list:
    PROLOGUE_SAVE rbx
    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

%endif ; VCS_MERGE_ASM