; =============================================================================
; File     : src/graph/bloom.asm
; Project  : Utkarsha VCS (vcs)
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: Bloom filters for per-path commit membership.
; =============================================================================

%ifndef VCS_GRAPH_BLOOM_ASM
%define VCS_GRAPH_BLOOM_ASM

%include "include/vcs.inc"

bits 64

section .text

; -----------------------------------------------------------------------------
; bloom_init — Initialize a bloom filter
; Input:  rdi = filter buffer, rsi = size in bits
; -----------------------------------------------------------------------------
global bloom_init
bloom_init:
    PROLOGUE_SAVE rbx, rcx
    mov     rbx, rdi
    mov     rcx, rsi
    shr     rcx, 3                ; bits to bytes
    xor     rax, rax
.init_loop:
    mov     [rbx + rax], byte 0
    inc     rax
    dec     rcx
    jnz     .init_loop
    EPILOGUE_RESTORE rbx, rcx
    ret

; -----------------------------------------------------------------------------
; bloom_add — Add an item to the bloom filter
; Input:  rdi = filter buffer, rsi = item hash (64-bit)
; -----------------------------------------------------------------------------
global bloom_add
bloom_add:
    PROLOGUE_SAVE rbx, rcx, rdx
    ; TODO: k hash functions, set bits
    EPILOGUE_RESTORE rbx, rcx, rdx
    ret

; -----------------------------------------------------------------------------
; bloom_test — Test if item might be in bloom filter
; Input:  rdi = filter buffer, rsi = item hash
; Output: rax = 1 if might contain, 0 if definitely not
; -----------------------------------------------------------------------------
global bloom_test
bloom_test:
    PROLOGUE_SAVE rbx
    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

%endif ; VCS_GRAPH_BLOOM_ASM