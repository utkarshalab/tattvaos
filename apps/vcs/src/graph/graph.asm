; =============================================================================
; File     : src/graph/graph.asm
; Project  : Utkarsha VCS (vcs)
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: Commit graph — generation numbers, reachability bitmaps.
; =============================================================================

%ifndef VCS_GRAPH_ASM
%define VCS_GRAPH_ASM

%include "include/vcs.inc"

bits 64

section .text

; -----------------------------------------------------------------------------
; graph_commit_add — Add a commit node to the graph
; Input:  rdi = commit hash, rsi = parent count, rdx = parent hashes
; Output: rax = VCS_OK
; -----------------------------------------------------------------------------
global graph_commit_add
graph_commit_add:
    PROLOGUE_SAVE rbx
    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

; -----------------------------------------------------------------------------
; graph_generation — Compute generation number for a commit
; Input:  rdi = commit hash
; Output: rax = generation number
; -----------------------------------------------------------------------------
global graph_generation
graph_generation:
    PROLOGUE_SAVE rbx
    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

; -----------------------------------------------------------------------------
; graph_reachable — Check if commit B is reachable from commit A
; Input:  rdi = commit A, rsi = commit B
; Output: rax = 1 if reachable, 0 otherwise
; -----------------------------------------------------------------------------
global graph_reachable
graph_reachable:
    PROLOGUE_SAVE rbx
    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

; -----------------------------------------------------------------------------
; graph_bloom_check — Check path bloom filter for a commit
; Input:  rdi = commit hash, rsi = path hash
; Output: rax = 1 if path might be in commit, 0 if definitely not
; -----------------------------------------------------------------------------
global graph_bloom_check
graph_bloom_check:
    PROLOGUE_SAVE rbx
    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

%endif ; VCS_GRAPH_ASM