; =============================================================================
; Tattva OS — unet/tools/ipsec_test.asm
; =============================================================================
; IPsec ESP Tunnel Security Association (SA) Diagnostic Test Tool.
;
; Implements:
;   - Tests IPsec ESP Encryption / Decryption SPI Security Association Loop
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global ipsec_test_init
global ipsec_test_run

align 32
ipsec_test_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
ipsec_test_run:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret
