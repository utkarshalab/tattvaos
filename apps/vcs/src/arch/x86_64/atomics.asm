; =============================================================================
; File     : src/arch/x86_64/atomics.asm
; Project  : Utkarsha VCS (vcs)
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: Atomic operations — compare-and-swap, fetch-add, barriers.
; =============================================================================

%ifndef VCS_ARCH_X86_64_ATOMICS_ASM
%define VCS_ARCH_X86_64_ATOMICS_ASM

%include "include/vcs.inc"

bits 64

section .text

; -----------------------------------------------------------------------------
; atomic_cas64 — Compare-and-swap 64-bit
; Input:  rdi = ptr, rsi = expected, rdx = desired
; Output: rax = previous value, ZF set if swapped
; -----------------------------------------------------------------------------
global atomic_cas64
atomic_cas64:
    PROLOGUE_SAVE rbx
    mov     rbx, rsi            ; expected into rbx (cmpxchg operand)
    mov     rax, rbx
    lock cmpxchg [rdi], rdx
    EPILOGUE_RESTORE rbx
    ret

; -----------------------------------------------------------------------------
; atomic_fetch_add64 — Atomic fetch-and-add 64-bit
; Input:  rdi = ptr, rsi = value to add
; Output: rax = previous value
; -----------------------------------------------------------------------------
global atomic_fetch_add64
atomic_fetch_add64:
    PROLOGUE_SAVE rbx
    mov     rbx, rsi
    lock xadd [rdi], rbx
    mov     rax, rbx
    EPILOGUE_RESTORE rbx
    ret

; -----------------------------------------------------------------------------
; atomic_load64 — Atomic load 64-bit (sequentially consistent)
; Input:  rdi = ptr
; Output: rax = loaded value
; -----------------------------------------------------------------------------
global atomic_load64
atomic_load64:
    PROLOGUE_SAVE rbx
    mov     rbx, [rdi]
    mfence
    mov     rax, rbx
    EPILOGUE_RESTORE rbx
    ret

; -----------------------------------------------------------------------------
; atomic_store64 — Atomic store 64-bit (sequentially consistent)
; Input:  rdi = ptr, rsi = value
; -----------------------------------------------------------------------------
global atomic_store64
atomic_store64:
    mfence
    mov     [rdi], rsi
    mfence
    ret

%endif ; VCS_ARCH_X86_64_ATOMICS_ASM