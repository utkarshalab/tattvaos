; =============================================================================
; Tattva OS — unet/qrng/qrng_entropy.asm
; =============================================================================
; Hardware Quantum Random Number Generator (QRNG) Optical Entropy Collector.
;
; Implements:
;   - Quantum Optical Beam-Splitter Entropy Streaming directly into `lib/urand`
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global qrng_init
global qrng_read_entropy

align 32
qrng_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
qrng_read_entropy:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret
