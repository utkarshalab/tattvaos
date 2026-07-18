; =============================================================================
; lib/io/dma/barrier.asm
; Memory barrier synchronization wrapper for DMA and hardware registers.
;
; Part of Utkarsha Labs / Tattva OS
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%ifndef IO_DMA_BARRIER_ASM
%define IO_DMA_BARRIER_ASM

%include "lib/io/macro/func.asm"

section .text

; =============================================================================
; dma_barrier — Wait for all previous memory operations to resolve
; In : None
; Out: None
; =============================================================================
IO_FUNC dma_barrier
    mfence                          ; Standard memory fence instruction
    ret
IO_ENDFUNC dma_barrier

%endif ; IO_DMA_BARRIER_ASM
