; =============================================================================
; lib/io/dma/sync.asm
; DMA Cache Sync (for CPU and Device access) implementing clflush loops.
;
; Part of Utkarsha Labs / Tattva OS
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%ifndef IO_DMA_SYNC_ASM
%define IO_DMA_SYNC_ASM

%include "lib/io/macro/func.asm"
%include "lib/io/macro/guard.asm"

section .data
global dma_coherency_flag
dma_coherency_flag: dq 1             ; 1 = coherent (default on x86_64), 0 = non-coherent

section .text

; =============================================================================
; dma_sync_for_cpu — Invalidate CPU cache lines before reading device DMA updates
; In : RDI = Virtual Address pointer
;      RSI = Buffer size in bytes
; Out: None
; RSO: RDI, RSI owned-in
; =============================================================================
IO_FUNC dma_sync_for_cpu
    guard_null rdi

    mov     rax, [rel dma_coherency_flag]
    test    rax, rax
    jnz     .done_coherent

    push    rax
    push    rcx
    push    rdi
    push    rsi

    mov     rax, rdi                ; RAX = current address pointer
    add     rsi, rax                ; RSI = end boundary address
    and     rax, ~63                ; Align to 64-byte cache line

.loop:
    cmp     rax, rsi
    jae     .done

    clflush [rax]                   ; Invalidate cache line (clflush does writeback+invalidate)

    add     rax, 64                 ; Advance by one cache line stride
    jmp     .loop

.done:
    mfence                          ; Wait for all flushes to complete in memory
    pop     rsi
    pop     rdi
    pop     rcx
    pop     rax
.done_coherent:
IO_ENDFUNC dma_sync_for_cpu

; =============================================================================
; dma_sync_for_device — Write back and invalidate CPU cache lines before device DMA
; In : RDI = Virtual Address pointer
;      RSI = Buffer size in bytes
; Out: None
; RSO: RDI, RSI owned-in
; =============================================================================
IO_FUNC dma_sync_for_device
    guard_null rdi

    mov     rax, [rel dma_coherency_flag]
    test    rax, rax
    jnz     .done_coherent

    push    rax
    push    rcx
    push    rdi
    push    rsi

    mov     rax, rdi
    add     rsi, rax
    and     rax, ~63

.loop:
    cmp     rax, rsi
    jae     .done

    clflush [rax]

    add     rax, 64
    jmp     .loop

.done:
    mfence
    pop     rsi
    pop     rdi
    pop     rcx
    pop     rax
.done_coherent:
IO_ENDFUNC dma_sync_for_device

%endif ; IO_DMA_SYNC_ASM
