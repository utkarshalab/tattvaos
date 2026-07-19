; =============================================================================
; lib/io/arch/x86_64/cache.asm
; Cache line management abstractions for x86_64 architectures.
;
; Provides unified interfaces for invalidation and writebacks to decouple
; memory-sync mechanisms from device driver loops.
;
; Part of Utkarsha Labs / Tattva OS
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%ifndef IO_ARCH_X86_64_CACHE_ASM
%define IO_ARCH_X86_64_CACHE_ASM

%include "lib/io/macro/func.asm"
%include "lib/io/macro/guard.asm"

section .text

global io_cache_flush
global io_cache_invalidate
global io_cache_writeback

; Helper internal routine to execute clflush loop
; In: RDI = start address, RSI = size in bytes
io_cache_loop:
    test    rsi, rsi
    jz      .done
    
    mov     rax, rdi
    add     rsi, rax                ; RSI = end boundary address
    and     rax, ~63                ; Align to 64-byte cache line boundary
    
.loop:
    cmp     rax, rsi
    jae     .done_loop
    clflush [rax]
    add     rax, 64
    jmp     .loop
    
.done_loop:
    mfence                          ; Enforce memory visibility of flushes
.done:
    ret

; =============================================================================
; io_cache_flush — Flush and invalidate cache lines in virtual range
; In : RDI = Virtual Address pointer
;      RSI = Length in bytes
; =============================================================================
IO_FUNC io_cache_flush
    guard_null rdi
    push    rsi
    push    rdi
    call    io_cache_loop
    pop     rdi
    pop     rsi
IO_ENDFUNC io_cache_flush

; =============================================================================
; io_cache_invalidate — Invalidate cache lines in virtual range
; In : RDI = Virtual Address pointer
;      RSI = Length in bytes
; =============================================================================
IO_FUNC io_cache_invalidate
    guard_null rdi
    push    rsi
    push    rdi
    call    io_cache_loop
    pop     rdi
    pop     rsi
IO_ENDFUNC io_cache_invalidate

; =============================================================================
; io_cache_writeback — Write back dirty cache lines in virtual range
; In : RDI = Virtual Address pointer
;      RSI = Length in bytes
; =============================================================================
IO_FUNC io_cache_writeback
    guard_null rdi
    push    rsi
    push    rdi
    call    io_cache_loop
    pop     rdi
    pop     rsi
IO_ENDFUNC io_cache_writeback

%endif ; IO_ARCH_X86_64_CACHE_ASM
