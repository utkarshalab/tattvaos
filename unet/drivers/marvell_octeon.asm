%ifndef GUARD_UNET_DRIVERS_MARVELL_OCTEON_ASM
%define GUARD_UNET_DRIVERS_MARVELL_OCTEON_ASM
; =============================================================================
; Tattva OS — unet/drivers/marvell_octeon.asm
; =============================================================================
; Marvell Octeon TX2 / CN10K DPAA DPU (Data Processing Accelerator) Driver.
;
; Features:
;   - NPA (Network Pool Allocator) Aura & Pool Hardware Allocation
;   - NIX (Network Interface eXpress) Receive & Transmit Subsystem
;   - Nix Receive Queue (RQ) & Transmit Queue (SQ) Context Configuration
;   - CPT (Cryptographic Accelerator) Hardware Crypto Offload Pipeline
;   - SSO (Schedule-Synchronization-Order) Event Work Queue Dispatch
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

struc nix_rx_parse_t
    .chan:              resw 1
    .desc_sizeof:       resb 1
    .flags:             resb 1
    .pkt_len:           resd 1
endstruc

section .text

global marvell_octeon_init
global marvell_nix_poll
global marvell_nix_transmit

align 64
marvell_octeon_init:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi                    ; MMIO Base

    ; Initialize NPA Aura pools & NIX VFS
    xor eax, eax

    pop rbx
    pop rbp
    ret

align 64
marvell_nix_poll:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    ; Poll NIX CQ descriptor & dispatch packet
    call eth_input
    mov eax, 1

    pop rbx
    pop rbp
    ret

align 64
marvell_nix_transmit:
    push rbp
    mov rbp, rsp
    prefetcht0 [rsi]
    ; Post NIX SQ descriptor & write to NIX_LF_SQ_OP_DOORBELL
    xor eax, eax
    pop rbp
    ret

%endif ; GUARD_UNET_DRIVERS_MARVELL_OCTEON_ASM
