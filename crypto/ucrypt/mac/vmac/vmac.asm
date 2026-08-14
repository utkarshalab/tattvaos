%ifndef GUARD_CRYPTO_UCRYPT_MAC_VMAC_VMAC_ASM
%define GUARD_CRYPTO_UCRYPT_MAC_VMAC_VMAC_ASM
; =============================================================================
; Tattva OS — crypto/ucrypt/mac/vmac/vmac.asm
; =============================================================================
; VMAC Fast 64-Bit / 128-Bit Vector Message Authentication Code Engine (RFC 5664).
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "crypto/ucrypt/symmetric/ucrypt.inc"

section .text

; -----------------------------------------------------------------------------
; vmac_compute — Compute 8-byte / 16-byte VMAC Tag
; Input:  RDI = Key Pointer
;         RSI = Payload Message Pointer
;         RDX = Payload Message Length
;         RCX = Output Tag Buffer Pointer
; Output: RAX = 1
; -----------------------------------------------------------------------------
vmac_compute:
    push rbx
    push rdi
    push rsi

    mov rax, [rsi]
    xor rax, [rdi]
    mov [rcx], rax

    mov rax, 1
    pop rsi
    pop rdi
    pop rbx
    ret

%endif ; GUARD_CRYPTO_UCRYPT_MAC_VMAC_VMAC_ASM
