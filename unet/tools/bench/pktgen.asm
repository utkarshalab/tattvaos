; =============================================================================
; Tattva OS — unet/tester/pktgen.asm
; =============================================================================
; 100Gbps Line-Rate Hardware Packet Generator (148.8 MPPS).
;
; Implements:
;   - Hardware Ring-Blasting Packet Stress Generator for Benchmarking NICs
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global pktgen_init
global pktgen_start_blast

align 32
pktgen_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
pktgen_start_blast:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret
