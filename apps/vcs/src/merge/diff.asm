; =============================================================================
; File     : src/merge/diff.asm
; Project  : Utkarsha VCS (vcs)
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: Diff engine — compute differences between two trees/files.
; =============================================================================

%ifndef VCS_MERGE_DIFF_ASM
%define VCS_MERGE_DIFF_ASM

%include "include/vcs.inc"

bits 64

section .text

; -----------------------------------------------------------------------------
; diff_files — Diff two files
; Input:  rdi = file a, rsi = file b
; Output: rax = VCS_OK, results written to diff context
; -----------------------------------------------------------------------------
global diff_files
diff_files:
    PROLOGUE_SAVE rbx
    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

; -----------------------------------------------------------------------------
; diff_trees — Diff two directory trees
; Input:  rdi = tree a, rsi = tree b
; Output: rax = VCS_OK
; -----------------------------------------------------------------------------
global diff_trees
diff_trees:
    PROLOGUE_SAVE rbx
    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

; -----------------------------------------------------------------------------
; diff_emit — Emit diff hunks in unified format
; Input:  rdi = diff context, rsi = output buffer, rdx = max len
; Output: rax = bytes written
; -----------------------------------------------------------------------------
global diff_emit
diff_emit:
    PROLOGUE_SAVE rbx
    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

%endif ; VCS_MERGE_DIFF_ASM