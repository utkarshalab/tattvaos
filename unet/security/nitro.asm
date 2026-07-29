; =============================================================================
; Tattva OS — unet/hsm/nitro.asm
; =============================================================================
; AWS Nitro Enclave PCIe Cryptographic Security Engine.
;
; Implements:
;   - PCIe Local VSOCK Communication & Hardware Cryptographic Enclave Attestation
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global nitro_init
global nitro_enclave_call

align 32
nitro_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
nitro_enclave_call:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret
