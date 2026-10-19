; =============================================================================
; File     : src/arch/x86_64/cache.asm
; Project  : Utkarsha VCS (vcs)
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: Cache control — prefetch, cache line flush, line size.
; =============================================================================

%ifndef VCS_ARCH_X86_64_CACHE_ASM
%define VCS_ARCH_X86_64_CACHE_ASM

%include "include/vcs.inc"

bits 64

section .data
align 16
cache_line_size:  dq 64

section .text

; -----------------------------------------------------------------------------
; cache_prefetch — Prefetch data into cache
; Input:  rdi = address, sil = locality hint (0-3)
; -----------------------------------------------------------------------------
global cache_prefetch
cache_prefetch:
    PROLOGUE_SAVE rbx
    mov     rbx, rdi
    cmp     sil, 0
    je      .t0
    cmp     sil, 1
    je      .t1
    cmp     sil, 2
    je      .t2
    jmp     .nta
.t0:
    prefetcht0 [rbx]
    jmp .done
.t1:
    prefetcht1 [rbx]
    jmp .done
.t2:
    prefetcht2 [rbx]
    jmp .done
.nta:
    prefetchnta [rbx]
.done:
    EPILOGUE_RESTORE rbx
    ret

; -----------------------------------------------------------------------------
; cache_flush_line — Flush cache line containing address
; Input:  rdi = address
; -----------------------------------------------------------------------------
global cache_flush_line
cache_flush_line:
    clflush [rdi]
    ret

; -----------------------------------------------------------------------------
; cache_get_line_size — Get cache line size in bytes
; Output: rax = bytes (typically 64)
; -----------------------------------------------------------------------------
global cache_get_line_size
cache_get_line_size:
    mov     rax, [cache_line_size]
    ret

%endif ; VCS_ARCH_X86_64_CACHE_ASM