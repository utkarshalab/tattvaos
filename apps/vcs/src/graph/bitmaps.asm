; =============================================================================
; File     : src/graph/bitmaps.asm
; Project  : Utkarsha VCS (vcs)
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: Reachability bitmaps for commit graph.
; =============================================================================

%ifndef VCS_GRAPH_BITMAPS_ASM
%define VCS_GRAPH_BITMAPS_ASM

%include "include/vcs.inc"

bits 64

section .text

; -----------------------------------------------------------------------------
; bitmap_build — Build reachability bitmap for a commit
; Input:  rdi = commit hash, rsi = output buffer
; Output: rax = bitmap size in bytes
; -----------------------------------------------------------------------------
global bitmap_build
bitmap_build:
    PROLOGUE_SAVE rbx
    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

; -----------------------------------------------------------------------------
; bitmap_merge — Merge two reachability bitmaps (OR)
; Input:  rdi = dst, rsi = src, rdx = size in bytes
; Output: none
; -----------------------------------------------------------------------------
global bitmap_merge
bitmap_merge:
    PROLOGUE_SAVE rbx, rcx
    mov     rbx, rdi
    mov     rcx, rdx
.merge_loop:
    test    rcx, rcx
    jz      .done
    mov     al, [rsi]
    or      [rdi], al
    inc     rdi
    inc     rsi
    dec     rcx
    jmp .merge_loop
.done:
    EPILOGUE_RESTORE rbx, rcx
    ret

; -----------------------------------------------------------------------------
; bitmap_contains — Test if commit is in bitmap
; Input:  rdi = bitmap, rsi = commit index, rdx = bitmap size
; Output: rax = 1 if present, 0 otherwise
; -----------------------------------------------------------------------------
global bitmap_contains
bitmap_contains:
    PROLOGUE_SAVE rbx
    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

%endif ; VCS_GRAPH_BITMAPS_ASM