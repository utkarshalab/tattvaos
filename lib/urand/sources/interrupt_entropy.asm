; =============================================================================
; Tattva OS — lib/urand/sources/interrupt_entropy.asm
; =============================================================================
; Hardware Interrupt Timing Jitter Harvester (IRQ & Packet Timing).
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "lib/urand/urand.inc"

section .text

; -----------------------------------------------------------------------------
; irq_feed_entropy — Feed IRQ timestamp & vector jitter into Fortuna pool
; Input:  RDI = Vector ID / IRQ Source ID
; Output: none
; -----------------------------------------------------------------------------
irq_feed_entropy:
    push rbx
    push rdx
    push rsi

    rdtsc                           ; High-precision timestamp
    shl rdx, 32
    or rax, rdx
    xor rax, rdi                    ; XOR with IRQ vector ID

    ; Feed timestamp into Fortuna pool 0
    call fortuna_pool_feed

    pop rsi
    pop rdx
    pop rbx
    ret
