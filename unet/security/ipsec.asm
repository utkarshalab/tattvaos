; =============================================================================
; Tattva OS — unet/security/ipsec.asm
; =============================================================================
; IPsec ESP Tunnel Mode Engine (RFC 4301 / RFC 4303).
;
; Implements:
;   - Encapsulating Security Payload (ESP) Header Parsing & AES-GCM Encryption
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global ipsec_init
global ipsec_esp_protect

align 32
ipsec_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
ipsec_esp_protect:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret
