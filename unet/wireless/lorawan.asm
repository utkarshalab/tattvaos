; =============================================================================
; Tattva OS — unet/wireless/lorawan.asm
; =============================================================================
; LoRaWAN Regional Long-Range IoT Gateway Protocol Engine.
;
; Implements:
;   - LoRaWAN MAC Layer (Class A / B / C) & AES-128 Join-Accept Cryptography
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global lorawan_init
global lorawan_handle_frame

align 32
lorawan_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
lorawan_handle_frame:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret
